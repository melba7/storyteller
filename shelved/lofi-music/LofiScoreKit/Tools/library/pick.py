"""Score the candidate lofi tracks for the eleven moods and pick a varied set for each.

Usage: python -I pick.py CANDIDATES.csv FEATURES.csv YAMNET_JSON_DIR OUT_DIR [EMBED.npz] [OVERRIDES.csv]

Evidence per track and mood, all on similar scales:
  tags   the site's own mood tags (free-stock-music.com only)
  title  words in the title, and the mood words HoliznaCC0 puts in brackets
  album  a hand-written prior for each Free Music Archive album
  genre  the site's genres, weakly
  model  a small classifier on YAMNet embeddings, trained on the site tags (optional)
  sound  where the audio sits in valence/arousal, from tempo, mode, brightness, busyness
  yam    YAMNet's AudioSet mood classes (happy, sad, tender, exciting, scary...)
Then hard filters (vocals, length, bitrate, holiday music, duplicates), a subtlety score
(steady, warm, sparse, little energy where speech lives) and a quality score.
"""
import json
import math
import os
import re
import sys
import hashlib

import numpy as np
import pandas as pd

MOODS = ["calm", "cozy", "playful", "hopeful", "melancholy", "mysterious",
         "tense", "somber", "romantic", "dreamy", "adventurous"]
ANCHOR = {
    "calm": (0.25, 0.15), "cozy": (0.55, 0.30), "playful": (0.60, 0.62), "hopeful": (0.70, 0.82),
    "melancholy": (-0.50, 0.20), "mysterious": (-0.10, 0.50), "tense": (-0.55, 0.85),
    "somber": (-0.70, 0.45), "romantic": (0.75, 0.40), "dreamy": (0.45, 0.45),
    "adventurous": (0.35, 0.78),
}
AMBIENCE = re.compile(r"^(Rain|Rain on surface|Raindrop|Water|Stream|Ocean|Waves, surf|Wind|"
                      r"Thunder|Thunderstorm|Bird|Bird vocalization, bird call, bird song|Chirp, tweet|"
                      r"Crackle|Fire|Vehicle|Train|Traffic noise, roadway noise|Crowd|Chatter)$")
TARGET = {m: 8 for m in MOODS}
TARGET["calm"] = 10  # the neutral default plays most

# free-stock-music.com mood tags -> moods
TAGMAP = {
    "Calm, Relaxing": {"calm": 0.8, "cozy": 0.2},
    "Gentle": {"calm": 0.4, "cozy": 0.4, "romantic": 0.3},
    "Smooth": {"cozy": 0.6, "calm": 0.2, "romantic": 0.2},
    "Dreamy": {"dreamy": 1.0},
    "Nostalgic": {"melancholy": 0.5, "cozy": 0.25, "dreamy": 0.15},
    "Pensive": {"melancholy": 0.5, "mysterious": 0.3, "calm": 0.15},
    "Melancholic": {"melancholy": 1.0},
    "Sad": {"melancholy": 0.7, "somber": 0.6},
    "Emotional": {"melancholy": 0.4, "romantic": 0.3, "hopeful": 0.2},
    "Romantic, Sentimental": {"romantic": 1.0},
    "Sensual": {"romantic": 0.7},
    "Positive": {"hopeful": 0.6, "playful": 0.4},
    "Bright": {"playful": 0.5, "hopeful": 0.5},
    "Happy, Cheerful": {"playful": 1.0, "hopeful": 0.3},
    "Funky": {"playful": 0.8},
    "Bouncy": {"playful": 0.8},
    "Cool": {"playful": 0.2, "cozy": 0.1},
    "Fashion, Lifestyle": {"playful": 0.3, "adventurous": 0.1},
    "Sporty": {"adventurous": 0.6, "playful": 0.3},
    "Driving": {"adventurous": 0.8, "tense": 0.2},
    "Energetic, Powerful": {"adventurous": 0.8},
    "Epic": {"adventurous": 0.8},
    "Inspirational": {"hopeful": 1.0},
    "Uplifting": {"hopeful": 1.0},
    "Motivational": {"hopeful": 0.8, "adventurous": 0.3},
    "Strange": {"mysterious": 0.8, "dreamy": 0.2},
    "Mysterious, Mystical": {"mysterious": 1.0},
    "Dark": {"somber": 0.4, "tense": 0.5, "mysterious": 0.4},
    "Moody": {"melancholy": 0.4, "mysterious": 0.3},
    "Criminal": {"tense": 0.6, "mysterious": 0.5},
    "Horror, Scary": {"tense": 1.0, "mysterious": 0.3},
    "Evil, Ominous": {"tense": 0.8, "somber": 0.3},
    "Sneaky, Spy": {"mysterious": 0.6, "playful": 0.3},
    "Dramatic, Suspenseful": {"tense": 1.0},
    "Rainy": {"melancholy": 0.4, "cozy": 0.4},
    "Meditation": {"calm": 0.8, "dreamy": 0.3},
}

# Title words -> moods. Each pattern is a regex matched on the lower-cased title.
LEX = [
    # calm
    (r"\bcalm|\bpeace|\bpeaceful|\bquiet\b|\bstill\b|\bserene|\btranquil|\bgentle|\bbreeze|\bdrift|\brelax|\bslowly\b|\bslow down|\bmeditat|\bexhale|\bbreathe|\bmellow|\bsoft\b|\bwetlands|\bcurrents?\b|\bunwind|\bease\b|\bidle\b|\bchill(ing|ax)?\b|\btheta\b|\bsky lake|\bcentered|\bsmooth sailing|\bstasis", {"calm": 1.0}),
    (r"\bocean|\bwaves?\b|\bwater|\blake\b|\btides?\b|\bshore|\bbeach|\bsand\b", {"calm": 0.6, "dreamy": 0.2}),
    # cozy
    (r"\bcozy|\bcosy|\bwarm\b|\bwarmth|\bcoffee|\btea\b|\bcuppa|\bchai\b|\bespresso|\bdecaf|\bhot chocolate|\bfire ?place|\bsweater|\bblanket|\bpillow|\bbook|\bpages\b|\bcooking|\bcookies?\b|\bramen|\bjelly|\bbath\b|\bbed\b|\bnap\b|\bpurr|\bbreakfast|\blunch\b|\bplants?\b|\blaundry|\bcomforts?\b|\bstuck inside|\bhugs?\b|\bstudio apartment|\bsaturday morning|\bwarm fuzz|\bhome\b|\bpaper mate|\bjunk drawer|\bgreen tea|\bday tea", {"cozy": 1.0}),
    (r"\brain|\bshowers?\b|\bpitter|\bumbrella|\bfoggy window", {"cozy": 0.5, "melancholy": 0.5}),
    (r"\bsnow|\bwinter|\bfrigid|\bcold hands|\bfreezing", {"cozy": 0.6, "calm": 0.3, "melancholy": 0.2}),
    # playful
    (r"\bplay\b|\bplaying|\bplayful|\bfun\b|\bhappy\b|\bjoy\b|\bbounc|\btoy\b|\bkids?\b|\bchilds? play|\bdanc(e|ing)\b|\bparty|\bgames?\b|\barcade|\bpixel|\bpuppy|\bkittens?|\bcat nip|\byarn|\bred dot|\btreat time|\bbubbles|\bdoodles|\bcandy|\bstrawberr|\bfrolic|\bskating|\bshopping|\bmustache|\bwait what|\bsqueaky|\bballerina|\bsandbox|\bsilly|\bcheer|\bwhistle|\bfunk|\bgroove|\bhot pepper|\bbicycles|\bwater skiing|\bgotta go|\bbirdie|\bmaggie|\bcookie fell|\bfresh fit|\bnew shoes|\bpoor, but happy|\bbusking|\bdandelions|\bbox of kittens|\bsnow angels|\bice skating|\bdo it\b|\bchop chops", {"playful": 1.0}),
    # hopeful
    (r"\bhope|\btomorrow|\bsunrise|\bdawn\b|\bmorning\b|\bnew day|\bbloom|\bflourish|\bspring\b|\bbright|\bsunlit|\bsunshine|\bsunlight|\bpurpose|\bforward|\bnever giving up|\bgood day|\bgood vibes|\bone good day|\bwish(es|ing)?\b|\bbelieve|\bfaithful|\bmeadows|\buplift|\binspir|\brun free|\btimeless\b|\bwaiting for the sun|\blook on the bright side|\blearning to love|\bfeeling human again|\bgood things ahead|\bearly bird|\bkomorebi|\bequinox|\bdon't forget to live|\bmotivat|\bsunny|\bwarm horizon|\bspring at last|\bspring in sight|\bhaircut|\btrying something new|\bmeteorites|\bhaving a good|\bit's going to be", {"hopeful": 1.0}),
    # melancholy
    (r"\bsad\b|\bsadness|\bsorrow|\blonely|\balone\b|\bsolitude|\btears|\bcry|\bmiss\b|\bmiss you|\bgoodbye|\bmemor|\bnostalgi|\bremember|\bforget|\bforgotten|\bin the past|\byesterday|\bused to\b|\bgone\b|\bautumn|\bgr[ae]y\b|\bblues\b|\blow tide|\bfaded|\bsigh\b|\bletting go|\bdepression|\bregret|\bempty|\bstranded|\blong day|\bloved me once|\blast day i saw|\bever see you again|\bdon'?t forget me|\bback home|\bseasons? change|\bwalking away|\bthe last long day|\baugust never lasts|\bsummer felt longer|\bnow and then|\bwhen i was human|\bkeep ?sakes|\bnobody needs you|\buseless\b|\bhiding in my room|\bthings? (we|i) used|\bsad boi|\bwe used to dance|\bthe way sad|\bshelter\b|\bwonder(ing)? why", {"melancholy": 1.0}),
    # mysterious
    (r"\bmyster|\bsecret|\bstrange|\bunknown|\bshadow|\bghosts?\b|\bhaunt|\bphantom|\bfog|\bmist\b|\bnocturne|\bnocturnal|\bmidnight|\bcaves?\b|\blabyrinth|\bdungeon|\babyss|\bvoid\b|\blimbo|\bdimension|\buniverse|\bcellar|\battic|\bstatic\b|\benigma|\bspy\b|\bnoir|\bserial|\bwolf\b|\bkitsune|\btengu|\btsukumogami|\byuki-onna|\bkodama|\btanuki|\bwitch|\bbrew\b|\bcarnival|\blilith|\bdeja vu|\bconfusion|\bwhispers|\bflickering|\bsleepwalk|\bpendulum|\bcaravan|\bpatchwork|\bsynthasia|\bmystventure|\bwonderland|\bcome one, come all|\bout there|\blittle green men|\bunder the floor|\bsomeones? in the attic|\bshadow self|\bcobwebs|\bgrave ?yard magic|\bthe old haunt|\bghost of|\bthe edge of nowhere|\bquestioning|\bnight roads|\bwhy\?|\bcave \d|\bhalloween|\bmushrooms|\bnight life|\bstreet lights", {"mysterious": 1.0}),
    # tense
    (r"\btension|\btense\b|\banxi|\bpanic|\bdanger|\bchase|\bfear|\bscary|\bhorror|\bterror|\bnightmare|\bthreat|\bwar\b|\bbattle|\bfight|\bcrash|\battack|\babducted|\bdevil|\btrauma|\bpsych ward|\buninvited|\bstrike of midnight|\bnot alone|\bcyber anxiety|\binternal panic|\bfires uptown|\bsolar flare|\bcrash landing|\bagoraphobia|\bcrime\b|\btrue grit|\bshowdown|\btragedy waiting|\btension in the air|\bthe dungeon|\bhaunted houses|\bfloor \d|\btrack \d|\bcyber crime|\bneo noir|\bturbulence", {"tense": 1.0}),
    # somber
    (r"\bgrief|\bmourn|\bfuneral|\brequiem|\bgrave\b|\btomb|\bdeath|\bdying|\bthe end\b|\bend of the world|\bbetween life and death|\btragedy|\bheavy\b|\bbroken\b|\bbleak|\bsolemn|\bsad ending|\bnothing i could do|\bi can'?t breathe|\bnever sleeping|\bnine to death|\bugly truth|\bhurts|\bdarkness|\bthe mother\b|\bthe father\b|\bgoodbye good times|\bhate myself|\bwon't need money|\bpower in the blood|\bsilent wood|\ba place to hide|\bsandstorm|\bexhale", {"somber": 1.0}),
    # romantic
    (r"\blove\b|\blover|\bromanc|\bromantic|\bheart\b|\bkiss|\bdarling|\bsweetheart|\bcrush\b|\bvalentine|\btogether|\bembrace|\bhold me|\bwith you\b|\bdreamin of u|\bfull of you|\bkind words|\bshe'?s near|\bsweet way|\bhoney|\bwedding|\bwaltz|\btender|\blonging|\byour eyes|\bbirds of a feather|\btake me with you|\bwish you were here|\bheart of the ocean|\bmessage in a bottle|\bshort walk with you|\bthat person again|\bi fell in love|\bfirst girl|\bi need you|\bplease don't go|\bfalling in love|\bpuppy love|\bpalm tree|\bsail away|\bstar bright|\bwarm wind|\btake care\b|\blife with you|\bi'?m still searching you|\bclose your eyes|\bsummer crush|\bmanifestations of the heart", {"romantic": 1.0}),
    # dreamy
    (r"\bdream|\bsleep|\blucid|\breverie|\bclouds?\b|\bsky\b|\bskies\b|\bstars?\b|\bstarry|\bmoon|\blunar|\bcelestial|\bgalaxy|\bmilky way|\bcosm|\bspace\b|\bastronaut|\bnebula|\bfloat|\bfluffy|\bballoon|\bsomnium|\baether|\bethereal|\bfair(y|ies)|\bfireflies|\bmagic|\bshimmer|\bglow|\bindigo|\blullab|\bdaydream|\binfinite|\becho|\borbs\b|\bbliss|\bsupernova|\bmeteor|\bsatellite|\bsubmarine|\bwhales?\b|\bpelagic|\bsaturn|\bpluto|\bquasar|\bneon|\bsynthetic|\bunderwater|\bcrescent|\bsomewhere new|\bvisions|\bout of the blue|\bwhen time called|\bmoon unit|\bcolor of a soul|\bbreak from reality|\btransient|\bdreamy", {"dreamy": 1.0}),
    # adventurous
    (r"\badventure|\bjourney|\bquest|\bvoyage|\btravel|\btrips?\b|\broad\b|\bdrive\b|\bdriving|\bride\b|\briding|\bexplor|\bdiscover|\bhorizon|\bwander|\bexpedition|\bfreeway|\bhighway|\btrain\b|\bflight|\bflying|\bsail\b|\bsailing|\bbike|\bnow or never|\bmoving forward|\bmovement\b|\bwestern|\bgame travel|\blast train|\bcolorado|\beighth day|\bkinetics|\bmagenta metropolis|\bcar ride|\bsunset drive|\bnight drive|\bnova bossa|\bjungle|\bwindows down|\bhooptie|\bday trips|\bsky scrapers|\bspace!|\bmoving landscapes|\btourism|\bon foot|\bcardboard box adventure|\bdangerous voyage|\bsolar flare|\bcrash landing|\bastroids|\bscroller|\bspace castle|\bburning in the atmosphere|\bwide open spaces|\bspace mountain|\bmetropolis|\bcyberfunk", {"adventurous": 1.0}),
]

# Hand-written priors for Free Music Archive albums (artist, album) -> moods.
ALBUM = {
    "A Good Book": {"cozy": 1.0},
    "Cat Nap": {"playful": 0.6, "cozy": 0.6},
    "Above the Clouds": {"dreamy": 1.0, "calm": 0.3},
    "Bloom": {"hopeful": 0.8, "playful": 0.3, "calm": 0.2},
    "Snowbound": {"cozy": 1.0, "calm": 0.3},
    "Nostalgia and Moving On": {"melancholy": 0.8, "hopeful": 0.3},
    "Mellow Skies": {"calm": 1.0, "dreamy": 0.4},
    "Just Relax": {"calm": 1.0, "cozy": 0.3},
    "Indigo Dreams": {"dreamy": 1.0},
    "Brain Fog": {"mysterious": 0.6, "dreamy": 0.6},
    "Now or Never": {"hopeful": 0.6, "adventurous": 0.4, "melancholy": 0.3},
    "Up All Night": {"cozy": 0.5, "playful": 0.3, "melancholy": 0.3},
    "Pelagic Journey": {"adventurous": 0.5, "dreamy": 0.5, "calm": 0.3},
    "Public Domain Lofi": {"calm": 0.4},
    "Lo-fi And Chill": {"calm": 0.3, "cozy": 0.3},
    "Be Happy With Who You Are": {"hopeful": 0.6, "romantic": 0.2},
    "City Slacker": {"cozy": 0.4, "playful": 0.4},
    "Townies": {"cozy": 0.4, "melancholy": 0.3},
    "An Ocean In Outer Space": {"dreamy": 0.8, "mysterious": 0.4},
    "Washed Up": {"calm": 0.4, "melancholy": 0.4},
    "Only In The Milky Way Part 1": {"dreamy": 0.6, "melancholy": 0.2},
    "Only In The Milky Way Part 2": {"dreamy": 0.6, "melancholy": 0.2},
    "Only In The Milky Way Part 3": {"dreamy": 0.6, "melancholy": 0.2},
    "Waves Of Nostalgia 2": {"melancholy": 0.5, "mysterious": 0.3, "tense": 0.2},
    "Tiny Plastic Video Games For Long Anxious Space Travel": {"playful": 0.4, "adventurous": 0.4, "tense": 0.2},
    "Beats From The Crypt": {"mysterious": 0.6, "tense": 0.6},
    "Everything Hurts": {"somber": 0.6, "melancholy": 0.6},
    "Lost": {"melancholy": 0.3, "dreamy": 0.3},
    "Horseless Headman ( Halloween Beats )": {"tense": 0.6, "mysterious": 0.6, "somber": 0.2},
    "All The Years I've Haunted (Part 1)": {"melancholy": 0.5, "mysterious": 0.4, "somber": 0.3},
    "All The Years I've Haunted (Part 2)": {"melancholy": 0.5, "mysterious": 0.4, "somber": 0.3},
    "All The Years I've Haunted (Part 3)": {"melancholy": 0.5, "mysterious": 0.4, "somber": 0.3},
    "War ( Game Commission )": {"tense": 0.8, "adventurous": 0.6},
    "Nature Spirit": {"mysterious": 0.7, "dreamy": 0.5},
    "Spring Woke Me Up": {"hopeful": 0.8},
    "Gamer Soundtrack: Haunted Mansion": {"mysterious": 0.6, "tense": 0.5},
    "The Hero and The Haunting": {"mysterious": 0.5, "somber": 0.5, "tense": 0.3},
    "Lullabies For The End Of The World": {"somber": 0.7, "dreamy": 0.4, "melancholy": 0.3},
    " Sci Fi )": {"mysterious": 0.7, "dreamy": 0.3},
    "Gamer Soundtrack: Caves": {"mysterious": 0.9, "tense": 0.3},
    "Winter Lofi": {"cozy": 0.7, "melancholy": 0.3},
    "OCEAN MEMORY ( Lo-fi Chill )": {"calm": 0.8, "melancholy": 0.3},
    "Summer Air ( Lo-fi )": {"hopeful": 0.4, "melancholy": 0.4, "playful": 0.2},
    "After Dark": {"mysterious": 0.6, "tense": 0.4},
    "A Small Town On Pluto": {"dreamy": 0.5, "mysterious": 0.5},
    "Busted Guitar (LOFI EDIT)": {"cozy": 0.4, "playful": 0.3},
    "Spring at last (LOFI TAPE)": {"hopeful": 0.8},
    "Gamer Soundtrack: Quiet Towns": {"calm": 0.6, "cozy": 0.4, "mysterious": 0.2},
    "Lazy Summer Lofi": {"cozy": 0.4, "playful": 0.4, "calm": 0.3},
    "Kick It (laid back HipHop)": {"cozy": 0.4, "calm": 0.3},
    "Chill Out": {"calm": 0.4},
    "Sad Beats": {"melancholy": 0.7},
}

GENRE = {
    "Halloween": {"tense": 0.5, "mysterious": 0.5},
    "Romantic": {"romantic": 1.0},
    "Synthwave": {"adventurous": 0.6}, "Chillwave": {"dreamy": 0.6}, "Vaporwave": {"dreamy": 0.5},
    "Ambient": {"calm": 0.5, "dreamy": 0.5}, "New Age": {"calm": 0.5, "dreamy": 0.4},
    "Ambient Electronic": {"dreamy": 0.5, "calm": 0.3},
    "Jazz-Hop": {"cozy": 0.5}, "Jazzy": {"cozy": 0.5}, "Lounge": {"cozy": 0.5}, "Jazz": {"cozy": 0.4},
    "Soundtrack": {"adventurous": 0.2, "mysterious": 0.2}, "Cinematic": {"adventurous": 0.3, "mysterious": 0.2},
    "Minimalism": {"calm": 0.3}, "Blues": {"melancholy": 0.3}, "Easy Listening": {"calm": 0.3},
    "Downtempo / Trip Hop": {"mysterious": 0.3, "dreamy": 0.2}, "Trip-Hop": {"mysterious": 0.3},
    "Experimental": {"mysterious": 0.2}, "Funk": {"playful": 0.5}, "Funk / Groove": {"playful": 0.5},
    "Sci-Fi": {"mysterious": 0.5}, "Goth": {"somber": 0.5, "mysterious": 0.3},
    "Classical": {"calm": 0.3, "romantic": 0.2}, "Piano": {"calm": 0.2, "romantic": 0.2},
}
EXCLUDE_GENRES = {
    # HoliznaCC0 files most themed albums under "Novelty" and Halloween under "Holiday",
    # so those two stay in.
    "Christmas", "Chiptune", "Chip Music", "Spoken", "Spoken Word", "Spoken Weird",
    "Radio Theater", "Sound Effects", "Noise", "Punk", "Loud-Rock", "Heavy Metal", "Industrial",
    "Techno", "Drum & Bass", "Drum & Bass / Breakbeat", "Gospel", "Musical Theater",
}
EXCLUDE_TITLE = re.compile(
    r"christmas|xmas|santa|deck the halls|silent night|holy night|angels we have heard|auld lang syne|jingle|"
    r"lunar new year|halloween soundscape", re.I)

# YAMNet AudioSet mood classes -> moods (z-scored log scores)
YAM = {
    "calm": {"m_tender": 0.4, "Lullaby": 0.3, "New-age music": 0.3, "m_exciting": -0.3},
    "cozy": {"m_tender": 0.3, "Jazz": 0.4, "Electric piano": 0.3},
    "playful": {"m_happy": 0.6, "m_funny": 0.4},
    "hopeful": {"m_happy": 0.5, "m_exciting": 0.3},
    "melancholy": {"m_sad": 0.7, "m_tender": 0.2},
    "mysterious": {"m_scary": 0.4, "Ambient music": 0.2, "Synthesizer": 0.2},
    "tense": {"m_scary": 0.5, "m_angry": 0.4, "m_exciting": 0.3},
    "somber": {"m_sad": 0.6, "m_scary": 0.2},
    "romantic": {"m_tender": 0.6, "Wedding music": 0.3},
    "dreamy": {"Ambient music": 0.4, "New-age music": 0.3, "Synthesizer": 0.2},
    "adventurous": {"m_exciting": 0.6, "Video game music": 0.2, "Soundtrack music": 0.2},
}


def num(v):
    s = str(v).strip().replace(",", "")
    if s in ("", "nan", "None"):
        return np.nan
    mult = 1
    if s[-1:] in "Kk":
        mult, s = 1000, s[:-1]
    elif s[-1:] in "Mm":
        mult, s = 1_000_000, s[:-1]
    try:
        return float(s) * mult
    except ValueError:
        return np.nan


def z(series):
    s = pd.to_numeric(series, errors="coerce")
    sd = s.std()
    return ((s - s.mean()) / (sd if sd and sd > 0 else 1)).fillna(0).clip(-3, 3)


def nice_title(title, artist):
    t = re.sub(r"\.mp3$", "", str(title)).strip()
    t = re.sub(r"^(fsm-team-escp-|fsm-team-|barradeen-escp-)", "", t)
    if " " not in t and "-" in t:
        t = t.replace("-", " ")
    return t


def add(target, mapping, weight):
    for mood, w in mapping.items():
        target[mood] = target.get(mood, 0.0) + w * weight


def lexicon(text):
    text = text.lower()
    out = {}
    for pattern, mapping in LEX:
        if re.search(pattern, text):
            add(out, mapping, 1.0)
    return out


def main():
    cand_path, feat_path, yam_dir, out_dir = sys.argv[1:5]
    embed_path = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] != "-" else None
    override_path = sys.argv[6] if len(sys.argv) > 6 else None
    os.makedirs(out_dir, exist_ok=True)

    cand = pd.read_csv(cand_path)
    feat = pd.read_csv(feat_path)
    feat["id"] = feat.path.str.extract(r"/(c\d{4})\.m4a$")[0]
    d = cand.merge(feat, on="id", how="left", suffixes=("", "_f"))
    d["title_clean"] = [nice_title(t, a) for t, a in zip(d.title, d.artist)]
    d["fav"] = d.favorites.map(num)
    d["lis"] = d.listens.map(num)
    d["dls"] = d.downloads.map(num)

    # YAMNet extras: style classes, the 'Music' score.
    extra = []
    for p in d.path.fillna(""):
        row = {}
        if p:
            jp = os.path.join(yam_dir, hashlib.sha1(p.encode()).hexdigest()[:16] + ".json")
            if os.path.exists(jp):
                j = json.load(open(jp))
                row.update(j.get("styles", {}))
                top = dict(j.get("top", []))
                row["music_score"] = top.get("Music", 0.0)
                # Rain, water, birds, fire or traffic recorded into the music itself.
                row["ambience"] = sum(v for k, v in top.items() if AMBIENCE.search(k))
                row["speech_mean"] = j.get("speech_mean", 0.0)
                row["singing_mean"] = j.get("singing_mean", 0.0)
                curve = np.array(j.get("vocal_curve", [0.0]))
                row["vocal_share20"] = float((curve > 0.2).mean())
                for k, v in j.get("moods", {}).items():
                    row["m_" + k.split()[0].lower()] = v
        extra.append(row)
    ex = pd.DataFrame(extra)
    for c in ex.columns:
        if c.startswith("m_") and c in d.columns:
            d[c] = d[c].fillna(ex[c])
        elif c not in d.columns:
            d[c] = ex[c].values

    # --- filters -----------------------------------------------------------------------
    reasons = {}

    def flag(i, why):
        reasons.setdefault(i, []).append(why)

    for i, r in d.iterrows():
        if pd.isna(r.get("duration")) or isinstance(r.get("error"), str) and r.get("error"):
            flag(i, "not analysed")
            continue
        genres = {g.strip() for g in str(r.genres).split(";")}
        if genres & EXCLUDE_GENRES:
            flag(i, "genre " + ",".join(sorted(genres & EXCLUDE_GENRES)))
        if EXCLUDE_TITLE.search(str(r.title)) or str(r.album).startswith("A Lo-Fi Christmas"):
            flag(i, "holiday or soundscape")
        if r.speech_frac > 0.02 or r.singing_frac > 0.02 or r.vocal_longest_s >= 2.5:
            flag(i, f"vocals (speech {r.speech_frac:.2f}, singing {r.singing_frac:.2f}, run {r.vocal_longest_s}s)")
        elif r.singing_mean > 0.02 or r.speech_mean > 0.015 or r.vocal_share20 > 0.05:
            # Sung or spoken parts mixed low: weak frame by frame, clear on average.
            flag(i, f"vocal-like throughout (singing {r.singing_mean:.3f}, speech {r.speech_mean:.3f}, "
                    f"{r.vocal_share20:.0%} of the track)")
        elif r.vocal_max > 0.35:
            # One short vocal chop or whisper under a narrator sounds like someone else speaking.
            flag(i, f"brief vocal sample (peak {r.vocal_max:.2f})")
        if r.duration < 75:
            flag(i, f"short {r.duration:.0f}s")
        if r.duration > 420:
            flag(i, f"long {r.duration:.0f}s")
        if r.lra > 15:
            # Big swings in level poke out from under the voice however low the bed sits.
            flag(i, f"wide dynamics (loudness range {r.lra:.0f} LU)")
        if r.music_score < 0.45:
            flag(i, f"not much music ({r.music_score:.2f})")
    # Duplicates: same artist family and title, or near-identical audio embedding.
    fam = d.artist.str.replace(r"\s*\((aka|ex\.)[^)]*\)", "", regex=True).str.lower().str.strip()
    tkey = d.title_clean.str.lower().str.replace(r"\(.*?\)|[^a-z0-9 ]", "", regex=True).str.strip()
    d["dupkey"] = fam + "|" + tkey
    order = d.assign(_br=d.bitrate_kbps.fillna(0), _dur=d.duration.fillna(0)).sort_values(
        ["_br", "_dur"], ascending=False)
    seen = {}
    for i, r in order.iterrows():
        if r.dupkey in seen:
            flag(i, f"duplicate of {d.loc[seen[r.dupkey], 'id']}")
        else:
            seen[r.dupkey] = i

    emb = None
    if embed_path and os.path.exists(embed_path):
        e = np.load(embed_path)
        pos = {k: n for n, k in enumerate(e["ids"])}
        emb = np.stack([e["mean"][pos[k]] if k in pos else np.zeros(e["mean"].shape[1]) for k in d.id])
        have = np.array([k in pos for k in d.id])
        unit = emb / (np.linalg.norm(emb, axis=1, keepdims=True) + 1e-9)
        sim = unit @ unit.T
        for a in range(len(d)):
            if not have[a]:
                continue
            for b in range(a + 1, len(d)):
                if have[b] and sim[a, b] > 0.997 and abs(d.duration[a] - d.duration[b]) < 4:
                    keep, drop = (a, b) if d.bitrate_kbps[a] >= d.bitrate_kbps[b] else (b, a)
                    flag(drop, f"same audio as {d.id[keep]}")

    d["excluded"] = ["; ".join(reasons.get(i, [])) for i in d.index]

    # --- evidence ----------------------------------------------------------------------
    ev = {k: pd.DataFrame(0.0, index=d.index, columns=MOODS) for k in
          ("tags", "title", "album", "genre", "model", "sound", "yam")}
    for i, r in d.iterrows():
        tags = [t.strip()[5:] for t in str(r.tags).split(";") if t.strip().startswith("mood:")]
        acc = {}
        for t in tags:
            add(acc, TAGMAP.get(t, {}), 1.0)
        for m, v in acc.items():
            ev["tags"].loc[i, m] = min(v, 1.5)
        title = r.title_clean
        acc = lexicon(title)
        for m, v in acc.items():
            ev["title"].loc[i, m] = min(v, 1.5)
        if r.source == "fma":
            for m, v in ALBUM.get(str(r.album), {}).items():
                ev["album"].loc[i, m] = v
        acc = {}
        for g in str(r.genres).split(";"):
            add(acc, GENRE.get(g.strip(), {}), 1.0)
        for m, v in acc.items():
            ev["genre"].loc[i, m] = min(v, 1.0)

    # Sound: valence/arousal from features.
    tempo = pd.to_numeric(d.tempo, errors="coerce")
    tempo_n = tempo.where(tempo <= 125, tempo / 2).where(lambda t: t >= 55, tempo * 2)
    d["tempo_n"] = tempo_n
    sign = np.where(d["mode"] == "major", 1.0, -1.0)
    arousal = (0.30 * z(d.onset_rate) + 0.25 * z(d.perc_ratio) + 0.20 * z(d.lufs)
               + 0.15 * z(d.centroid) + 0.10 * z(tempo_n))
    valence = (0.45 * z(sign * d.mode_clarity.abs().fillna(0) + 0.0 * sign) + 0.25 * z(d.centroid)
               + 0.15 * z(np.log(d.m_happy.fillna(1e-4) + 1e-4) - np.log(d.m_sad.fillna(1e-4) + 1e-4))
               + 0.15 * z(tempo_n))
    d["v_hat"] = (valence.rank(pct=True) * 1.5 - 0.75).round(2)
    d["a_hat"] = (arousal.rank(pct=True) * 0.8 + 0.1).round(2)
    for m in MOODS:
        va, ar = ANCHOR[m]
        dist = np.sqrt((d.v_hat - va) ** 2 + (2 * (d.a_hat - ar)) ** 2)
        ev["sound"][m] = z(-dist) * 0.35

    # YAMNet mood classes
    for m, mapping in YAM.items():
        acc = pd.Series(0.0, index=d.index)
        for col, w in mapping.items():
            if col in d.columns:
                acc += w * z(np.log(pd.to_numeric(d[col], errors="coerce").fillna(1e-5) + 1e-5))
        ev["yam"][m] = acc * 0.25

    # Optional model on embeddings, trained on the site tags.
    if emb is not None:
        from sklearn.linear_model import LogisticRegression
        from sklearn.decomposition import PCA
        from sklearn.model_selection import cross_val_predict
        from sklearn.metrics import roc_auc_score
        X = np.hstack([PCA(n_components=48, random_state=0).fit_transform(emb),
                       np.column_stack([z(d[c]) for c in ("onset_rate", "perc_ratio", "lufs", "centroid",
                                                           "tempo_n", "mode_clarity", "lra", "bass")])])
        lab = d.source == "fsm"
        report = []
        for m in MOODS:
            y = (ev["tags"][m] >= 0.5).astype(int).values
            if lab.sum() == 0 or y[lab.values].sum() < 8:
                continue
            clf = LogisticRegression(C=0.3, max_iter=2000, class_weight="balanced")
            p_cv = cross_val_predict(clf, X[lab.values], y[lab.values], cv=5, method="predict_proba")[:, 1]
            auc = roc_auc_score(y[lab.values], p_cv)
            clf.fit(X[lab.values], y[lab.values])
            p = clf.predict_proba(X)[:, 1]
            p[lab.values] = p_cv
            report.append(f"{m}: {y[lab.values].sum()} tagged, cross-validated AUC {auc:.2f}")
            if auc >= 0.68:
                ev["model"][m] = (p - 0.5) * 1.2 * min(1.0, (auc - 0.6) / 0.25)
        open(os.path.join(out_dir, "model-report.txt"), "w").write("\n".join(report) + "\n")

    W = {"tags": 1.0, "title": 1.0, "album": 0.6, "genre": 0.3, "model": 0.6, "sound": 1.0, "yam": 1.0}
    total = sum(ev[k] * w for k, w in W.items())
    why = {}
    for m in MOODS:
        parts = pd.DataFrame({k: ev[k][m] * w for k, w in W.items()})
        why[m] = parts.apply(lambda row: " ".join(f"{k}{v:+.1f}" for k, v in row.items() if abs(v) >= 0.15), axis=1)

    # Hand overrides: id, mood, weight (e.g. "c0123,tense,1.0" or "c0123,*,-9" to drop).
    if override_path and os.path.exists(override_path):
        ov = pd.read_csv(override_path, comment="#")
        for r in ov.itertuples():
            idx = d.index[d.id == r.id]
            if len(idx) == 0:
                continue
            if r.mood == "*":
                total.loc[idx, :] += r.weight
            else:
                total.loc[idx, r.mood] += r.weight

    # Subtlety and quality.
    d["subtle"] = (-0.30 * z(d.lra) - 0.25 * z(d.presence) - 0.20 * z(d.onset_rate)
                   - 0.15 * z(d.centroid) - 0.10 * z(d.dyn)).round(2)
    fav = np.log1p(d.fav.fillna(0))
    fav_z = ((fav - fav[d.source == "fma"].mean()) / (fav[d.source == "fma"].std() or 1)).where(
        d.source == "fma", 0.3).clip(-2, 2)
    br = pd.to_numeric(d.bitrate_kbps, errors="coerce").fillna(320)
    d["quality"] = (0.35 * fav_z + np.where(br < 160, -0.8, np.where(br >= 256, 0.15, 0.0))
                    + np.where(d.duration.between(120, 330), 0.15, np.where(d.duration < 100, -0.3, 0.0))
                    + np.where(d.lufs < -24, -0.3, 0.0) + np.where(d.lra > 12, -0.4, 0.0)
                    + np.where(d.license.str.contains("SA", na=False), -0.05, 0.0)).round(2)

    for m in MOODS:
        d["s_" + m] = total[m].round(2)
        d["why_" + m] = why[m]
        # What people said about the track (site tags, title, album, genre, and the model
        # trained on the tags), as opposed to what the audio features suggest.
        d["sem_" + m] = sum(ev[k][m] * W[k] for k in ("tags", "title", "album", "genre", "model")).round(2)
    s = total.values
    top = s.argmax(axis=1)
    srt = np.sort(s, axis=1)
    d["best"] = [MOODS[k] for k in top]
    d["margin"] = (srt[:, -1] - srt[:, -2]).round(2)

    # --- selection ---------------------------------------------------------------------
    pool = d[d.excluded == ""].copy()
    picks = []
    taken = set()
    # Fill the scarcest moods first so they get first call on shared tracks.
    supply = {m: int(((pool["s_" + m] >= pool[[f"s_{x}" for x in MOODS]].max(axis=1) - 0.25)
                      & (pool["s_" + m] > 0.6)).sum()) for m in MOODS}
    order = sorted(MOODS, key=lambda m: supply[m])
    for m in order:
        other = pool[[f"s_{x}" for x in MOODS if x != m]].max(axis=1)
        fit = pool["s_" + m] - 0.6 * (other - pool["s_" + m]).clip(lower=0)
        energetic = m in ("playful", "hopeful", "tense", "adventurous")
        # The atmosphere layer adds rain or birds only when the story has them, so music
        # with its own rain or birds recorded in loses a little.
        amb_pen = (2.0 * (pool.ambience.fillna(0) - 0.06)).clip(0, 0.4)
        rank = fit + (0.15 if energetic else 0.35) * pool.subtle + 0.35 * pool.quality - amb_pen
        cands = pool.assign(fit=fit.round(2), rank=rank.round(2), other=other).sort_values("rank", ascending=False)
        chosen = []
        for strict in (True, False):
          for i, r in cands.iterrows():
            if len(chosen) >= TARGET[m]:
                break
            if r.id in taken:
                continue
            if r.subtle < -1.0:
                continue  # the busiest 2% of the pool never goes under a narrator
            if strict and (r["s_" + m] < 1.0 or r["s_" + m] < r.other - 0.2 or r["sem_" + m] < 0.5):
                continue
            if not strict and (r["s_" + m] < 0.8 or r["s_" + m] < r.other - 0.5 or r["sem_" + m] < 0.3):
                continue
            group = r.album if r.source == "fma" else r.artist
            cap = 3 if m in ("tense", "somber", "mysterious", "romantic") else 2
            if sum(1 for c in chosen if (c.album if c.source == "fma" else c.artist) == group) >= cap:
                continue
            if sum(1 for c in chosen if c.artist == r.artist) >= 4:
                continue
            if any(abs((c.tempo_n or 0) - (r.tempo_n or 0)) < 3 and c.key == r.key and c["mode"] == r["mode"]
                   for c in chosen):
                continue
            r = r.copy()
            r["pass"] = "strict" if strict else "relaxed"
            chosen.append(r)
            taken.add(r.id)
        for n, r in enumerate(chosen, 1):
            picks.append({"mood": m, "n": n, **r.to_dict()})
    pk = pd.DataFrame(picks)
    cols = ["mood", "n", "id", "pass", "artist", "album", "title_clean", "license", "fit", "rank", "subtle", "quality",
            "tempo_n", "key", "mode", "lufs", "lra", "duration", "bitrate_kbps", "best", "margin",
            "ambience", "fav", "page_url", "local_path"]
    pk[cols].to_csv(os.path.join(out_dir, "picks.csv"), index=False)
    d.to_csv(os.path.join(out_dir, "scored.csv"), index=False)

    with open(os.path.join(out_dir, "review.txt"), "w") as out:
        out.write(f"pool {len(d)}, eligible {len(pool)}, excluded {len(d) - len(pool)}\n")
        out.write("supply (tracks scoring >0.6 near their best): " + ", ".join(f"{m} {supply[m]}" for m in MOODS) + "\n\n")
        for m in MOODS:
            sel = pk[pk.mood == m]
            out.write(f"== {m.upper()} ({len(sel)})\n")
            for r in sel.to_dict("records"):
                out.write(f"  {r['id']} {r['fit']:5.2f} {r['pass'][:3]} sub{r['subtle']:+.2f} q{r['quality']:+.2f} "
                          f"{r['tempo_n']:4.0f}bpm {r['key']}{'m' if r['mode'] == 'minor' else ''} "
                          f"{r['lufs']:5.1f}LUFS lra{r['lra']:4.1f} {r['duration']:4.0f}s amb{r['ambience']:.2f} {r['license']} | "
                          f"{r['artist']} | {r['album'] if r['source'] == 'fma' else ''} | {r['title_clean']}\n"
                          f"        [{r['why_' + m]}]\n")
            alt = pool[~pool.id.isin(taken)].assign(f=pool["s_" + m]).sort_values("f", ascending=False).head(6)
            for r in alt.itertuples():
                out.write(f"    alt {r.id} {r.f:5.2f} best={r.best} | {r.artist} | {r.title_clean}\n")
            out.write("\n")
        ex = d[d.excluded != ""]
        out.write(f"== EXCLUDED ({len(ex)})\n")
        for r in ex.itertuples():
            out.write(f"  {r.id} {r.excluded} | {r.artist} | {r.title_clean}\n")
    print(open(os.path.join(out_dir, "review.txt")).read()[:6000])


if __name__ == "__main__":
    main()
