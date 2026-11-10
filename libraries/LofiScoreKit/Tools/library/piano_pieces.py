"""What is known about classical piano pieces: which mood each one suits.

Used by pick_piano.py. A piece is identified from its title by form, opus and number
(or Brown catalogue number for Chopin's works without opus), so the same piece is found
whatever the recording's title looks like. Weights are 0 to about 1.3; a piece can lean
toward several moods. "storm" marks pieces with a loud or fast middle section, which
makes them poor beds under a narrator however sad the rest is.
"""
import re

M, S, Y = "melancholy", "somber", "mysterious"

# (form, opus or "b", number) -> moods
CHOPIN = {
    ("nocturne", 9, 1): {M: 1.0, "dreamy": 0.3},
    ("nocturne", 9, 2): {"romantic": 1.0, "calm": 0.3},
    ("nocturne", 9, 3): {"romantic": 0.5, "playful": 0.3, "storm": 1},
    ("nocturne", 15, 1): {"calm": 0.5, "tense": 0.4, "storm": 1},
    ("nocturne", 15, 2): {"dreamy": 0.6, "romantic": 0.6},
    ("nocturne", 15, 3): {Y: 0.9, S: 0.5, M: 0.3},
    ("nocturne", 27, 1): {Y: 0.8, S: 0.7, "storm": 1},
    ("nocturne", 27, 2): {"romantic": 1.0, "dreamy": 0.4},
    ("nocturne", 32, 1): {"calm": 0.5, "romantic": 0.5},
    ("nocturne", 32, 2): {"romantic": 0.7, "storm": 1},
    ("nocturne", 37, 1): {M: 0.8, S: 0.5},
    ("nocturne", 37, 2): {"dreamy": 0.6, "calm": 0.5},
    ("nocturne", 48, 1): {S: 1.1, M: 0.4, "storm": 1},
    ("nocturne", 48, 2): {M: 0.8, Y: 0.4},
    ("nocturne", 55, 1): {M: 1.0},
    ("nocturne", 55, 2): {"romantic": 0.7},
    ("nocturne", 62, 1): {"dreamy": 0.6, "romantic": 0.5},
    ("nocturne", 62, 2): {"romantic": 0.6, "dreamy": 0.4, "storm": 1},
    ("nocturne", 72, 1): {M: 1.0},
    ("nocturne", "b", 49): {M: 1.1},           # C sharp minor, Lento con gran espressione
    ("nocturne", "b", 108): {M: 0.9, S: 0.4},   # C minor, posthumous
    ("prelude", 28, 2): {Y: 0.9, S: 0.8},
    ("prelude", 28, 4): {S: 0.9, M: 0.8},
    ("prelude", 28, 6): {M: 1.0, S: 0.5},
    ("prelude", 28, 8): {"tense": 0.9, "storm": 1},
    ("prelude", 28, 13): {"calm": 0.6, "romantic": 0.4},
    ("prelude", 28, 15): {M: 0.6, Y: 0.4, S: 0.4, "calm": 0.3, "storm": 1},
    ("prelude", 28, 17): {"romantic": 0.7},
    ("prelude", 28, 20): {S: 1.3},
    ("prelude", 28, 21): {"calm": 0.5, "romantic": 0.5},
    ("prelude", 28, 24): {"tense": 1.0, "storm": 1},
    ("prelude", 45, 1): {Y: 0.9, M: 0.6, "dreamy": 0.4},
    ("etude", 10, 3): {M: 0.6, "romantic": 0.6, "storm": 1},
    ("etude", 10, 6): {S: 1.0, Y: 0.7, M: 0.4},
    ("etude", 25, 1): {"dreamy": 1.0},
    ("etude", 25, 7): {M: 0.9, S: 0.8},
    ("waltz", 34, 2): {M: 1.0},
    ("waltz", 64, 2): {M: 0.8, "playful": 0.2},
    ("waltz", 69, 1): {M: 0.8, "romantic": 0.5},
    ("waltz", 69, 2): {M: 0.9},
    ("waltz", 70, 2): {M: 0.7, "romantic": 0.3},
    ("waltz", 332, 1): {M: 0.9},                 # "Valse melancolique", attributed
    ("waltz", "b", 150): {M: 0.9},               # A minor, posthumous
    ("waltz", "b", 56): {"playful": 0.5, "tense": 0.4},
    ("mazurka", 6, 1): {M: 0.6},
    ("mazurka", 6, 2): {Y: 0.5, M: 0.5},
    ("mazurka", 7, 2): {M: 0.5, "playful": 0.3},
    ("mazurka", 7, 3): {M: 0.4, "tense": 0.3},
    ("mazurka", 17, 2): {M: 0.8},
    ("mazurka", 17, 4): {M: 0.8, Y: 0.8},
    ("mazurka", 24, 1): {M: 0.8},
    ("mazurka", 24, 4): {M: 0.7, Y: 0.4},
    ("mazurka", 30, 1): {M: 0.8},
    ("mazurka", 30, 4): {Y: 0.5, M: 0.5, "tense": 0.3},
    ("mazurka", 33, 4): {M: 0.7, "playful": 0.2},
    ("mazurka", 41, 1): {M: 0.5, Y: 0.5, "storm": 1},
    ("mazurka", 41, 2): {M: 0.7, S: 0.6},
    ("mazurka", 50, 3): {M: 0.6, Y: 0.4},
    ("mazurka", 56, 3): {M: 0.5, Y: 0.5},
    ("mazurka", 59, 1): {M: 0.7, Y: 0.3},
    ("mazurka", 59, 3): {"tense": 0.4, "playful": 0.4},
    ("mazurka", 63, 2): {M: 0.9},
    ("mazurka", 63, 3): {M: 0.9},
    ("mazurka", 67, 2): {M: 0.8},
    ("mazurka", 67, 4): {M: 0.8},
    ("mazurka", 68, 2): {M: 0.7},
    ("mazurka", 68, 4): {S: 0.8, M: 0.7, Y: 0.4},
    ("mazurka", "b", 134): {M: 0.6},
    ("mazurka", "b", 140): {M: 0.6},
    ("funeral march", 72, 2): {S: 1.3},
    ("berceuse", 57, 1): {"dreamy": 1.0, "calm": 0.5},
    ("barcarolle", 60, 1): {"romantic": 0.7, "dreamy": 0.4, "storm": 1},
    ("largo", "b", 109): {"calm": 0.6, S: 0.4},
    ("fantaisie impromptu", 66, 1): {"tense": 0.6, "romantic": 0.3, "storm": 1},
}
FORMS = [("fantaisie impromptu", r"fantaisie.{0,3}impromptu"),
         ("nocturne", r"nocturne"), ("prelude", r"pr[eé]lude"), ("etude", r"[eé]tude|\bstudy\b"),
         ("mazurka", r"mazurk"), ("waltz", r"waltz|valse"), ("funeral march", r"funeral march|marche fun[eè]bre"),
         ("berceuse", r"berceuse"),
         ("barcarolle", r"barcarol"), ("impromptu", r"impromptu"), ("largo", r"\blargo\b"),
         ("contredanse", r"contredanse"), ("albumleaf", r"album ?leaf|albumblatt|feuille d'album")]
DANCES = {"waltz", "mazurka", "contredanse", "polonaise"}

# Bach, Goldberg Variations (BWV 988), by variation number. The slow minor-key variations
# (15, 21, 25) are the dark heart of the set; the fast hand-crossing ones are busy.
GOLDBERG = {
    "aria": {"calm": 0.9, "dreamy": 0.3, M: 0.2},
    13: {"romantic": 0.5, "calm": 0.5, "dreamy": 0.3},
    15: {M: 0.8, Y: 0.7, S: 0.4},
    21: {S: 0.8, M: 0.6, Y: 0.4},
    25: {S: 1.0, M: 0.9, Y: 0.4},
    **{n: {"calm": 0.4, "dreamy": 0.2} for n in (3, 9, 12, 18, 24, 27)},
    **{n: {"playful": 0.5, "hopeful": 0.3} for n in (2, 4, 6, 7, 10, 16, 19, 22, 30)},
    **{n: {"playful": 0.6, "tense": 0.3, "storm": 1} for n in (1, 5, 8, 11, 14, 17, 20, 23, 26, 28, 29)},
}

# Other composers, matched on the lower-cased "title | album | artist"; the first match wins.
OTHER = [
    (r"gnossienne", {Y: 1.4}),
    (r"gymnop[eé]die.*\b(no\.?|n[°º]|#)? ?1\b|premi[eè]re gymnop", {M: 1.0, "calm": 0.5}),
    (r"gymnop[eé]die.*\b(no\.?|n[°º]|#)? ?2\b", {Y: 0.6, "dreamy": 0.6, M: 0.4}),
    (r"gymnop[eé]die.*\b(no\.?|n[°º]|#)? ?3\b", {M: 0.9, S: 0.5}),
    (r"gymnop[eé]die", {M: 0.6, "calm": 0.4}),
    (r"moonlight|mondschein|quasi una fantasia|sonata no\.? ?14", {S: 1.0, Y: 0.7, M: 0.3}),
    (r"path[eé]tique.*(adagio|2nd|second|\bii\b)", {"romantic": 0.6, M: 0.5}),
    (r"f[uü]r elise", {M: 0.4, "playful": 0.3}),
    (r"d\.? ?960.{0,40}(andante|\bii\b|-02-)", {S: 0.9, M: 0.7, Y: 0.3}),
    (r"d\.? ?959.{0,40}(andantino|\bii\b|-02-)", {M: 0.9, S: 0.4, "storm": 1}),
    (r"d\.? ?568.{0,40}andante", {M: 0.8, S: 0.4}),
    (r"d\.? ?784.{0,40}andante", {"calm": 0.5, Y: 0.4}),
    (r"d\.? ?664.{0,40}andante", {"calm": 0.6, M: 0.5}),
    (r"menuett|minuet|scherzo|rondo|allegr|presto|vivace", {"playful": 0.6}),
    (r"schubert.*(andante|adagio|lento)|(andante|adagio|lento).*schubert", {M: 0.4, "calm": 0.3}),
    (r"des pas sur la neige|footsteps in the snow", {S: 1.0, Y: 0.7}),
    (r"la cath[eé]drale engloutie|sunken cathedral", {Y: 1.0}),
    (r"voiles\b|canope|feuilles mortes|brouillards", {Y: 1.0, "dreamy": 0.4}),
    (r"clair de lune", {"dreamy": 1.3}),
    (r"r[eê]verie", {"dreamy": 1.0}),
    (r"la fille aux cheveux de lin", {"romantic": 0.8, "calm": 0.5}),
    (r"tr[aä]umerei", {"dreamy": 1.0, "romantic": 0.3}),
    (r"f[uü]rchtenmachen|frightening", {Y: 0.9}),
    (r"kind im einschlummern|child falling asleep", {Y: 0.5, "dreamy": 0.5}),
    (r"der dichter spricht|poet speaks", {M: 0.6, Y: 0.5}),
    (r"nuages gris|lugubre gondol|unstern", {Y: 1.2, S: 0.6}),
    (r"consolation", {"calm": 0.6, "romantic": 0.5}),
    (r"\bnotturno\b", {Y: 0.6, "romantic": 0.4}),
    (r"solitary traveller|einsamer wanderer|heimweh|homesick", {M: 0.9}),
    (r"gondellied|venetian boat|gondola song", {M: 0.8, Y: 0.5}),
    (r"\boctober\b|autumn song|chanson triste|sad song", {M: 1.0}),
    (r"intermezzo.*op\.? ?118.*\bno\.? ?6\b|intermezzo in e.?flat minor", {S: 0.9, Y: 0.8}),
    (r"intermezzo.*op\.? ?117.*\bno\.? ?2\b|intermezzo in b.?flat minor", {M: 0.9}),
    (r"intermezzo.*op\.? ?117.*\bno\.? ?3\b", {S: 0.7, Y: 0.6}),
    (r"intermezzo.*op\.? ?119.*\bno\.? ?1\b", {Y: 0.7, M: 0.6}),
    (r"bwv ?853|prelude.{0,30}e.?flat minor", {S: 1.0, M: 0.5}),
    (r"bwv ?867|prelude.{0,30}b.?flat minor", {S: 0.9, M: 0.6}),
    (r"bwv ?849|bwv ?869", {M: 0.7, S: 0.4}),
    (r"marche fun[eè]bre|funeral march", {S: 1.3}),
    (r"\belegie\b|\belegy\b|[eé]l[eé]gie|lament", {S: 0.9, M: 0.6}),
]


def chopin(text):
    """(form, moods) for a Chopin title; moods is {} when the piece is not in the table."""
    form = next((name for name, pattern in FORMS if re.search(pattern, text)), "")
    opus = re.search(r"\bop\.? ?(?:posth\.? ?)?(\d+)", text)
    number = re.search(r"\bno\.? ?(\d+)\b", text)
    brown = re.search(r"\bb\. ?(\d+)", text)
    key = None
    if opus:
        key = (form, int(opus.group(1)), int(number.group(1)) if number else 1)
    elif brown:
        key = (form, "b", int(brown.group(1)))
    moods = dict(CHOPIN.get(key, {}))
    if not moods and form:
        minor = bool(re.search(r"\bminor\b", text))
        if form in ("etude",):
            moods = {"tense": 0.6, "playful": 0.4, "storm": 1}
        elif form in DANCES or form == "impromptu":
            moods = {M: 0.4} if minor else {"playful": 0.5, "romantic": 0.3}
        else:
            moods = {M: 0.4} if minor else {"calm": 0.3, "romantic": 0.3}
    return form, moods


def goldberg(text):
    if not re.search(r"goldberg|bwv\.? ?988", text):
        return None
    m = re.search(r"variation ?(\d{1,2})|\bvar\.? ?(\d{1,2})\b", text)
    if m:
        return dict(GOLDBERG.get(int(m.group(1) or m.group(2)), {}))
    if re.search(r"aria", text.replace("variation", "")):
        return dict(GOLDBERG["aria"])
    return {}


def classical(text, composer):
    """(form, moods) from the tables above; moods may hold the extra key "storm"."""
    if composer == "chopin":
        return chopin(text)
    g = goldberg(text)
    if g is not None:
        return "variation", g
    for pattern, moods in OTHER:
        if re.search(pattern, text):
            return "", dict(moods)
    return "", {}


PRELUDE_KEYS = {2: "A minor", 4: "E minor", 6: "B minor", 8: "F-sharp minor", 13: "F-sharp major",
                15: "D-flat major, 'Raindrop'", 17: "A-flat major", 20: "C minor", 21: "B-flat major",
                24: "D minor"}
ROMAN = ["", "I", "II", "III", "IV", "V", "VI"]
SMALL = {"In", "On", "The", "Of", "Da", "And", "Molto"}


def _uncamel(s):
    words = re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", " ", s).split()
    out = []
    for n, w in enumerate(words):
        out.append(w.lower() if (n and w in SMALL) or w in ("Major", "Minor", "Flat", "Sharp") else w)
    t = " ".join(out)
    t = re.sub(r"\b([A-G]) (flat|sharp)\b", r"\1-\2", t)
    return t


def display_title(title):
    """A readable title for file names and credits; the recordings' own titles vary a lot."""
    t = str(title).strip()
    if re.match(r"MoonlightSonataMv1", t):
        return "Moonlight Sonata, Op. 27 No. 2 - I. Adagio sostenuto"
    m = re.match(r"JohannSebastianBach-\d+-GoldbergVariationsBwv\.988-(.+)$", t)
    if m:
        part = m.group(1)
        v = re.match(r"Variation(\d+)(?:\.(.+))?$", part)
        if v:
            extra = f" ({_uncamel(v.group(2))})" if v.group(2) else ""
            return f"Goldberg Variations, BWV 988 - Variation {v.group(1)}{extra}"
        return "Goldberg Variations, BWV 988 - " + _uncamel(part).replace("Aria da Capo", "Aria da capo")
    m = re.match(r"FranzSchubert-(.+?)D\.(\d+)-(\d+)-(.+)$", t)
    if m:
        work = _uncamel(m.group(1))
        return f"{work}, D. {m.group(2)} - {ROMAN[int(m.group(3))]}. {_uncamel(m.group(4))}"
    t = t.replace("Mazurkaa", "Mazurka").replace("♭", "-flat").replace("♯", "-sharp")
    t = re.sub(r"\b([A-G]) (flat|sharp)\b", r"\1-\2", t)
    t = re.sub(r"\bno\. ?(\d+)", r"No. \1", t)
    t = re.sub(r"Op\. ?(\d+), No\.", r"Op. \1 No.", t)
    m = re.match(r"Preludes, Op\. 28 - No\. (\d+)", t)
    if m and int(m.group(1)) in PRELUDE_KEYS:
        return f"Prelude in {PRELUDE_KEYS[int(m.group(1))]}, Op. 28 No. {m.group(1)}"
    m = re.match(r"Nocturnes, Op\. (\d+) - No\. (\d+)\. Nocturne in (.+)$", t)
    if m:
        return f"Nocturne in {m.group(3)}, Op. {m.group(1)} No. {m.group(2)}"
    m = re.match(r"(Etude|Mazurka|Nocturne) Op\. (\d+) No\. (\d+) in ([A-G][\w-]* (?:major|minor))", t)
    if m:
        form = "Étude" if m.group(1) == "Etude" else m.group(1)
        return f"{form} in {m.group(4)}, Op. {m.group(2)} No. {m.group(3)}"
    t = re.sub(r"^Nocturne in E minor, Op\. posth\. 72$", "Nocturne in E minor, Op. posth. 72 No. 1", t)
    t = re.sub(r"\s*\(Op\. posth\.\)$", "", t)
    return re.sub(r"\s+", " ", t).strip()
