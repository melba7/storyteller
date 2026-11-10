#!/usr/bin/env python3
"""Build the scene-scoring test set (cases.jsonl) from public-domain books.

Each case below names a passage by the words its last sentence ends with (`at`) in
one of the books in Tools/data/books/json (fetched by Tools/data/fetch_books.py and
split by make_readaloud.py), how many sentences lead up to it (`n`, default 12), the
memory the scorer is shown with it, and what the right answer is. The labels were
written by reading the passages, not by running the scorer, so the set measures the
scorer rather than agreeing with it.

    python3 -I Tools/atmosphere/eval/build_cases.py            # writes cases.jsonl, prints a review
    python3 -I Tools/atmosphere/eval/build_cases.py --check    # only report anchors that fail

The expectations (see SceneEvalCase in Sources/LofiAtmosphere/Eval/SceneEval.swift):
  place      "new", "none", "any", or a place id from the case's memory
  setting    indoors | outdoors | vehicle ("vehicle|outdoors" accepts either)
  main       families any of which may be the loudest sound
  required   families that must be there; forbidden: families that must not
  kinds      {family: [acceptable kinds]} when the family is in the scene
  state      words any of which should be in the state note ([] = no note)
  moment     none | swell | hush;  oneShot: none | a one-off sound id ("a|b" accepts either)
  transition transitions any of which fit, or ["none"]
  sinceAt    words of the sentence where the story enters the scene (resolved to expect.since,
             the sentence's first six words); since "none" = the scene was already under way
  heard      false when silence is as good as a sound
Families, kinds, one-off sounds and transitions are checked against Tools/atmosphere/catalog.json.
"""
from __future__ import annotations

import json
import pathlib
import sys

CATALOG = pathlib.Path(__file__).resolve().parent.parent / "catalog.json"

HERE = pathlib.Path(__file__).resolve().parent
BOOKS = HERE.parent.parent / "data" / "books" / "json"
OUT = HERE / "cases.jsonl"

# A few memories reused across a book's cases.
DRACULA_CASTLE = {
    "world": "Transylvania, the Carpathians, the 1890s; travelling by coach",
    "places": [
        {"id": "p1", "name": "the Golden Krone hotel, Bistritz", "setting": "indoors", "sounds": "murmur soft, fireplace faint", "state": "evening, the dining room"},
        {"id": "p2", "name": "Harker's room in Castle Dracula", "setting": "indoors", "sounds": "roomTone.castleChamber faint, wind faint", "state": "night, supper with the Count"},
    ],
    "current": "p2",
}
WHITBY = {
    "world": "Whitby, on the Yorkshire coast, August, the 1890s",
    "places": [
        {"id": "p1", "name": "the churchyard seat on the East Cliff, Whitby", "setting": "outdoors", "sounds": "seaShore.cliffs soft, wind faint, birdsong faint", "state": "afternoon"},
        {"id": "p2", "name": "Whitby harbour and the piers", "setting": "outdoors", "sounds": "seaShore.harbour soft, murmur faint", "state": "a dead calm, sultry night"},
    ],
    "current": "p2",
}
BENBOW = {
    "world": "the English coast, the 1700s; a country inn by a cove",
    "places": [
        {"id": "p1", "name": "the Admiral Benbow inn", "setting": "indoors", "sounds": "murmur soft, fireplace faint", "state": "evening, the captain drinking in the parlour"},
    ],
    "current": "p1",
}
HISPANIOLA = {
    "world": "the 1700s; a schooner bound for a treasure island",
    "places": [
        {"id": "p1", "name": "the Admiral Benbow inn", "setting": "indoors", "sounds": "murmur soft, fireplace faint"},
        {"id": "p2", "name": "the Hispaniola, at anchor off Bristol", "setting": "vehicle", "sounds": "ship soft, seaShore.harbour faint", "state": "night, loading"},
    ],
    "current": "p2",
}
SCROOGE = {
    "world": "London, Christmas Eve, the 1840s; cold and foggy",
    "places": [
        {"id": "p1", "name": "Scrooge's counting-house", "setting": "indoors", "sounds": "roomTone faint, fireplace faint, clock faint", "state": "Christmas Eve, foggy and cold"},
        {"id": "p2", "name": "Scrooge's bedroom", "setting": "indoors", "sounds": "roomTone.houseAtNight faint, clock faint", "state": "night, dark"},
    ],
    "current": "p2",
}
FEZZIWIG = {
    "world": "London, the 1800s, Christmas; Scrooge shown his past by a spirit",
    "places": [
        {"id": "p1", "name": "Scrooge's bedroom", "setting": "indoors", "sounds": "roomTone.houseAtNight faint, clock faint"},
        {"id": "p2", "name": "Fezziwig's warehouse", "setting": "indoors", "sounds": "emptyHall.warehouse soft, clock faint", "state": "seven o'clock, shutting up for Christmas Eve"},
    ],
    "current": "p2",
}
CRATCHITS = {
    "world": "London, Christmas, the 1840s; Scrooge shown the future by a spirit",
    "places": [
        {"id": "p1", "name": "the Cratchits' house, Camden Town", "setting": "indoors", "sounds": "murmur.dinnerTable soft, fireplace soft, kitchen.homeKitchen faint", "state": "Christmas dinner, lively"},
        {"id": "p2", "name": "London streets with the Ghost", "setting": "outdoors", "sounds": "oldTown soft", "state": "day"},
    ],
    "current": "p2",
}
BAKER_STREET = {
    "world": "London, 1889; Sherlock Holmes's rooms",
    "places": [
        {"id": "p1", "name": "the sitting room at 221B Baker Street", "setting": "indoors", "sounds": "fireplace soft, oldTown faint, clock faint", "state": "morning, breakfast"},
    ],
    "current": "p1",
}
SECRET_GARDEN_WINTER = {
    "world": "Misselthwaite Manor on the Yorkshire moor, Edwardian England; late winter",
    "places": [
        {"id": "p1", "name": "the secret garden", "setting": "outdoors", "sounds": "wind soft, birdsong faint", "state": "winter, grey and bare"},
        {"id": "p2", "name": "Mary's room at Misselthwaite", "setting": "indoors", "sounds": "roomTone faint, wind faint"},
    ],
    "current": "p2",
}
TOAD_HALL = {
    "world": "the English river bank, Edwardian; animals who live like gentlemen",
    "places": [
        {"id": "p1", "name": "Toad Hall", "setting": "indoors", "sounds": "roomTone faint, clock faint", "state": "a quiet afternoon"},
        {"id": "p2", "name": "the river bank", "setting": "outdoors", "sounds": "river soft, birdsong faint"},
    ],
    "current": "p2",
}

CASES = [
    # ---- Dracula --------------------------------------------------------------------
    dict(id="dr-castle-room-morning", book="dracula", ch=1, at="except the howling of wolves", n=14,
         about="Harker alone in his room at the castle by day; wolves heard habitually, not now",
         tags=["place", "oneShot", "state"], memory=DRACULA_CASTLE,
         expect=dict(place="p2", setting="indoors", main=["roomTone", "wind", "emptyHall"],
                     forbidden=["crowd", "city", "murmur"], oneShot="none", moment="none", transition=["none"], since="none")),
    dict(id="dr-castle-wolves-howl", book="dracula", ch=3, at="answered from far and wide by the howling of wolves", n=12,
         about="at his window at night; the Count calls and the wolves howl now",
         tags=["oneShot", "place"], memory=DRACULA_CASTLE,
         expect=dict(place="p2", setting="indoors", oneShot="wolfHowl", forbidden=["crowd", "city"])),
    dict(id="dr-castle-door", book="dracula", ch=1, at="clanking of massive bolts drawn back", n=12,
         about="at the castle door at night after the coach; chains and bolts",
         tags=["place", "sounds"],
         memory={"world": "Transylvania, the 1890s", "current": "p2", "places": [
             {"id": "p1", "name": "the Golden Krone hotel, Bistritz", "setting": "indoors", "sounds": "murmur soft, fireplace faint"},
             {"id": "p2", "name": "the caleche through the Borgo Pass", "setting": "vehicle", "sounds": "horses soft, wind soft, nightForest faint", "state": "night, wolves about"}]},
         expect=dict(place="new", setting="outdoors", main=["wind", "nightForest", "emptyHall", "roomTone", "horses"],
                     forbidden=["crowd", "city"], oneShot="chainsRattle")),
    dict(id="dr-whitby-calm", book="dracula", ch=6, at="in the great harmony of nature's silence", n=10,
         about="the harbour on the sultry still night before the storm (a newspaper cutting)",
         tags=["state", "sounds"], memory=WHITBY,
         expect=dict(place="p2", setting="outdoors", main=["seaShore", "wind", "murmur", "oldTown"],
                     forbidden=["strongWind", "thunder", "heavyRain", "crowd"], state=["calm", "still", "sultry", "silence", "quiet"], moment="none",
                     transition=["none"], since="none")),
    dict(id="dr-whitby-tempest-breaks", book="dracula", ch=6, at="without warning the tempest broke", n=12,
         about="the moment the storm breaks over the harbour",
         tags=["transition", "state"], memory=WHITBY, sinceAt="Then without warning the tempest broke",
         expect=dict(place="p2", setting="outdoors", main=["strongWind", "seaShore", "heavyRain", "thunder", "wind"],
                     moment="swell", state=["storm", "tempest", "gale", "break"], transition=["stormBreaks"])),
    dict(id="dr-whitby-storm-height", book="dracula", ch=6, at="clung with grim clasp to the iron stanchions", n=8,
         about="the storm at its height on the piers",
         tags=["sounds", "kinds"],
         memory={"world": WHITBY["world"], "current": "p2", "places": WHITBY["places"][:1] + [
             {"id": "p2", "name": "Whitby harbour and the piers", "setting": "outdoors", "sounds": "seaShore.stormySea full, strongWind soft", "state": "the tempest breaking"}]},
         expect=dict(place="p2", setting="outdoors", main=["strongWind", "seaShore", "heavyRain"], required=["strongWind"],
                     kinds={"seaShore": ["stormySea", "cliffs", "harbour"]}, forbidden=["city", "roomTone"], since="none")),
    dict(id="dr-mina-cliff-evening", book="dracula", ch=5, at="a Salvation Army meeting in a back street", n=10,
         about="Mina alone on the cliff seat at nine in the evening, sheep bleating, a band far off",
         tags=["sounds"], memory={"world": WHITBY["world"], "places": WHITBY["places"][:1], "current": "none"},
         expect=dict(place="p1", setting="outdoors", main=["seaShore", "wind", "oldTown", "nightInsects", "birdsong", "farmyard"],
                     forbidden=["crowd", "city", "roomTone"], state=["evening", "night", "nine", "dusk"])),
    dict(id="dr-knock-hall-door", book="dracula", ch=9, at="there was a knock at the hall-door", n=10,
         about="going downstairs in Lucy's house when someone knocks",
         tags=["oneShot"],
         memory={"world": "Hillingham, a house near London, the 1890s", "current": "p1", "places": [
             {"id": "p1", "name": "Lucy's bedroom, Hillingham", "setting": "indoors", "sounds": "roomTone faint", "state": "morning, Lucy ill"}]},
         expect=dict(place="any", setting="indoors", oneShot="doorKnock", forbidden=["crowd", "city"])),
    dict(id="dr-knock-bath", book="dracula", ch=11, at="there was a knock at the hall door", n=8,
         about="chafing Lucy in a bath when someone knocks at the hall door",
         tags=["oneShot"],
         memory={"world": "Hillingham, the 1890s", "current": "p1", "places": [
             {"id": "p1", "name": "Lucy's bedroom, Hillingham", "setting": "indoors", "sounds": "roomTone faint", "state": "morning after the wolf"}]},
         expect=dict(place="any", setting="indoors", oneShot="doorKnock", forbidden=["crowd", "city"])),
    dict(id="dr-cock-crow", book="dracula", ch=3, at="Then came the welcome cock-crow, and I felt that I was safe", n=8,
         about="dawn in the castle; the cock crows",
         tags=["oneShot"], memory=DRACULA_CASTLE,
         expect=dict(place="p2", setting="indoors", oneShot="roosterCrow")),
    dict(id="dr-mist-in-room", book="dracula", ch=18, at="not through the window, but through the joinings of the door", n=12,
         about="Mina in bed at night, mist pouring into the room, half dreaming",
         tags=["state", "sounds"],
         memory={"world": "Dr Seward's asylum at Purfleet, near London, autumn, the 1890s", "current": "p1", "places": [
             {"id": "p1", "name": "the Harkers' room at the asylum", "setting": "indoors", "sounds": "roomTone.houseAtNight faint", "state": "night"}]},
         expect=dict(place="p1", setting="indoors", main=["roomTone", "deepDrone", "clock", "wind"],
                     forbidden=["crowd", "city", "murmur", "birdsong"], state=["night", "fog", "mist", "dream", "dark"], since="none")),
    dict(id="dr-funeral-harbour", book="dracula", ch=6, at="stood on it when the time came and saw everything", n=8,
         about="the sea captain's funeral seen from the churchyard seat, boats in the harbour",
         tags=["sounds", "place"], memory={"world": WHITBY["world"], "places": WHITBY["places"], "current": "none"},
         expect=dict(place="p1", setting="outdoors", main=["seaShore", "wind", "murmur", "oldTown", "crowd", "birdsong"],
                     forbidden=["city", "roomTone"])),
    dict(id="dr-demeter-log-storm", book="dracula", ch=6, at="they only told him there was something, and crossed themselves", n=12,
         about="the Demeter's log at sea: under way in the Mediterranean, the crew uneasy",
         tags=["sounds"],
         memory={"world": "the Demeter, a Russian schooner, Varna to Whitby, the 1890s", "current": "p1", "places": [
             {"id": "p1", "name": "the Demeter at sea", "setting": "vehicle", "sounds": "ship soft, openSea soft", "state": "under way"}]},
         expect=dict(place="p1", setting="vehicle", main=["ship", "openSea", "strongWind", "wind"], forbidden=["city", "crowd", "roomTone"])),
    dict(id="dr-chapter-heading", book="dracula", ch=0, at="jagged line against the moonlit sky", n=6,
         extra=["CHAPTER II", "JONATHAN HARKER'S JOURNAL—continued"],
         about="the passage ends on the next chapter's heading, which has not said where the story is",
         tags=["place"], memory=DRACULA_CASTLE,
         expect=dict(place="none", heard=False)),
    # ---- Treasure Island ------------------------------------------------------------
    dict(id="ti-benbow-captain-arrives", book="treasure-island", ch=0, at="Yo-ho-ho, and a bottle of rum!\"", n=4,
         about="the old seaman arrives at the inn door above the cove",
         tags=["place", "sounds"],
         expect=dict(place="new", setting="outdoors", main=["seaShore", "wind", "birdsong", "farmyard"], forbidden=["crowd", "city", "roomTone"])),
    dict(id="ti-benbow-stories", book="treasure-island", ch=0, at="wild deeds and places on the Spanish Main", n=10,
         about="the captain's dreadful stories of storms at sea, told in the parlour: remembered places do not count",
         tags=["place"], memory=BENBOW,
         expect=dict(place="p1", setting="indoors", main=["murmur", "fireplace", "roomTone", "crowd"],
                     forbidden=["openSea", "ship", "strongWind", "seaShore", "thunder"], transition=["none"], since="none")),
    dict(id="ti-benbow-doctor", book="treasure-island", ch=0, at="Drink and the devil had done for the rest—Yo-ho-ho, and a bottle of rum!\"", n=8,
         about="the doctor in the parlour with the country folk and the drunk captain",
         tags=["place", "sounds"], memory=BENBOW,
         expect=dict(place="p1", setting="indoors", main=["murmur", "fireplace", "roomTone"], forbidden=["crowd", "city"])),
    dict(id="ti-blind-man-leaves", book="treasure-island", ch=2, at="tap-tap-tapping into the distance", n=10,
         about="the blind man leaves the parlour; his stick taps away down the road",
         tags=["sounds"],
         memory={"world": BENBOW["world"], "current": "p1", "places": [
             {"id": "p1", "name": "the Admiral Benbow inn", "setting": "indoors", "sounds": "roomTone faint, fireplace faint", "state": "morning, the captain alone in the parlour"}]},
         expect=dict(place="p1", setting="indoors", forbidden=["crowd"], since="none")),
    dict(id="ti-counting-coins-frost", book="treasure-island", ch=3, at="the tap-tapping of the blind man's stick upon the frozen road", n=10,
         about="Jim and his mother alone at night counting the dead captain's coins; the inn silent, frost outside",
         tags=["state", "oneShot"], memory=BENBOW,
         expect=dict(place="p1", setting="indoors", main=["roomTone", "clock", "fireplace", "wind"],
                     forbidden=["murmur", "crowd"], state=["night", "frost", "silent", "still", "quiet", "alone", "dead"])),
    dict(id="ti-bristol-quays", book="treasure-island", ch=6, at="The smell of tar and salt was something new", n=8,
         about="walking along the Bristol quays among ships and sailors",
         tags=["sounds"],
         expect=dict(place="new", setting="outdoors", main=["seaShore", "crowd", "oldTown", "ship", "murmur", "city"],
                     kinds={"seaShore": ["harbour", "pier"], "oldTown": ["harbourTown"], "city": ["docks"]}, forbidden=["roomTone", "forest"])),
    dict(id="ti-hispaniola-capstan", book="treasure-island", ch=9, at="the men bustling to their places in the glimmer of the ship's lanterns", n=3,
         about="on deck before dawn as the crew mans the capstan",
         tags=["sounds", "place"], memory={"world": HISPANIOLA["world"], "places": HISPANIOLA["places"][:1], "current": "none"},
         expect=dict(place="new", setting="vehicle", main=["ship", "crowd", "seaShore", "openSea", "murmur"], forbidden=["city", "roomTone"])),
    dict(id="ti-voyage-chorus", book="treasure-island", ch=9, at="And then the whole crew bore chorus:—", n=8,
         about="the crew sings as the anchor comes up",
         tags=["place"], memory=HISPANIOLA,
         expect=dict(place="p2", setting="vehicle", main=["ship", "crowd", "seaShore", "openSea"], oneShot="none")),
    dict(id="ti-hispaniola-sails", book="treasure-island", ch=9, at="begun her voyage to the Isle of Treasure", n=6,
         about="the ship sets off: a swell",
         tags=["transition"], memory=HISPANIOLA, sinceAt="begun her voyage to the Isle of Treasure",
         expect=dict(place="p2", setting="vehicle", main=["ship", "openSea", "crowd", "seaShore", "wind"], moment="swell", transition=["vehicleDeparts"])),
    dict(id="ti-apple-barrel", book="treasure-island", ch=10, at="returned the voice of the coxswain, Israel Hands", n=10,
         about="Jim hidden in the apple barrel on deck at night, pirates talking low beside it",
         tags=["sounds"], memory={"world": HISPANIOLA["world"], "current": "p2", "places": HISPANIOLA["places"][:1] + [
             {"id": "p2", "name": "the Hispaniola at sea", "setting": "vehicle", "sounds": "ship soft, openSea soft", "state": "a fine night, the last of the voyage"}]},
         expect=dict(place="p2", setting="vehicle", main=["ship", "openSea", "murmur"], forbidden=["crowd", "city"], since="none")),
    dict(id="ti-jolly-boat", book="treasure-island", ch=15, at="in the direction of the stockade upon the chart", n=8,
         about="rowing ashore in the jolly-boat",
         tags=["sounds"],
         memory={"world": "a treasure island in the Caribbean, the 1700s", "current": "p1", "places": [
             {"id": "p1", "name": "the Hispaniola, anchored off the island", "setting": "vehicle", "sounds": "ship soft, seaShore faint", "state": "hot, the pitch bubbling"}]},
         expect=dict(place="new", setting="vehicle", main=["seaShore", "openSea", "ship"], kinds={"openSea": ["rowingBoat"]}, forbidden=["city", "crowd"])),
    dict(id="ti-stockade", book="treasure-island", ch=15, at="shot the others like partridges", n=8,
         about="the log-house and stockade on a knoll among the trees",
         tags=["sounds"],
         memory={"world": "a treasure island in the Caribbean, the 1700s", "current": "p1", "places": [
             {"id": "p1", "name": "the beach where the jolly-boat landed", "setting": "outdoors", "sounds": "seaShore soft, forest faint"}]},
         expect=dict(place="any", setting="outdoors", main=["forest", "birdsong", "wind", "seaShore", "nightInsects"], forbidden=["crowd", "city", "roomTone"])),
    dict(id="ti-coracle-night", book="treasure-island", ch=21, at="there were but two points visible on the whole anchorage", n=8,
         about="Jim sets out at night in the fog with the coracle; pirates' fire far off",
         tags=["state", "sounds"],
         memory={"world": "a treasure island in the Caribbean, the 1700s", "current": "p1", "places": [
             {"id": "p1", "name": "the stockade log-house", "setting": "indoors", "sounds": "roomTone faint, forest faint"}]},
         expect=dict(place="new", setting="outdoors", main=["seaShore", "nightInsects", "wind", "swamp", "nightForest"],
                     forbidden=["crowd", "city", "roomTone"], state=["night", "dark", "fog", "black"])),
    dict(id="ti-benbow-dead-captain", book="treasure-island", ch=3, at="we advanced into the parlour", n=8,
         about="back in the inn's parlour at night with the dead captain: the same inn under another name",
         tags=["place", "state"], memory=BENBOW,
         expect=dict(place="p1", setting="indoors", forbidden=["murmur", "crowd"], state=["night", "dark", "dead", "silent", "alone", "empty"])),
    # ---- A Christmas Carol ----------------------------------------------------------
    dict(id="cc-marley-dead", book="a-christmas-carol", ch=0, at="that Marley was as dead as a door-nail", n=10,
         about="the narrator's reflections before the story starts: no place at all",
         tags=["place"],
         expect=dict(place="none", heard=False)),
    dict(id="cc-counting-house", book="a-christmas-carol", ch=0, at="old Scrooge sat busy in his counting-house", n=6,
         about="Scrooge at work in his counting-house on a cold foggy Christmas Eve",
         tags=["place", "sounds"],
         expect=dict(place="new", setting="indoors", main=["roomTone", "clock", "fireplace", "oldTown"], forbidden=["crowd", "city", "murmur"])),
    dict(id="cc-clanking-chain", book="a-christmas-carol", ch=0, at="a heavy chain over the casks", n=10,
         about="Scrooge alone at night hears the house bells ring and then a chain dragged below",
         tags=["oneShot", "state"],
         memory={"world": "London, Christmas Eve, the 1840s", "current": "p1", "places": [
             {"id": "p1", "name": "Scrooge's rooms", "setting": "indoors", "sounds": "fireplace faint, roomTone faint", "state": "evening, alone with his gruel"}]},
         expect=dict(place="p1", setting="indoors", main=["roomTone", "fireplace", "clock", "deepDrone"], forbidden=["crowd", "city"],
                     state=["night", "dark", "alone", "fear", "dread", "silent"], oneShot="chainsRattle")),
    dict(id="cc-chimes-quarters", book="a-christmas-carol", ch=1, at="the chimes of a neighbouring church struck the four quarters", n=2, lead=6,
         about="Scrooge wakes in the dark; a church clock chimes the quarters",
         tags=["oneShot"], memory=SCROOGE,
         expect=dict(place="p2", setting="indoors", oneShot="clockChime|bellToll")),
    dict(id="cc-fezziwig-closing", book="a-christmas-carol", ch=1, at="looked up at the clock, which pointed to the hour of seven", n=10,
         about="a warehouse at closing time on Christmas Eve, Fezziwig at his desk",
         tags=["place"], memory={"world": FEZZIWIG["world"], "places": FEZZIWIG["places"][:1], "current": "p1"},
         expect=dict(place="new", setting="indoors", main=["roomTone", "emptyHall", "clock", "hushedRoom", "workshop", "fireplace"], forbidden=["crowd", "city"])),
    dict(id="cc-fezziwig-dance", book="a-christmas-carol", ch=1, at="away they all went, twenty couple at once", n=12,
         about="the warehouse turned into a ballroom: the same place in a new state, the dance starting",
         tags=["state", "transition"], memory=FEZZIWIG, sinceAt="In came a fiddler",
         expect=dict(place="p2", setting="indoors", main=["crowd"], kinds={"crowd": ["partyIndoors", "ballroom", "feastHall"]},
                     state=["dance", "party", "ball", "music", "fiddler"], moment="swell|none", transition=["crowdGathers", "none"])),
    dict(id="cc-christmas-morning-streets", book="a-christmas-carol", ch=2, at="in their best clothes, and with their gayest faces", n=8,
         about="Christmas morning streets, shops shutting, steeples calling people to church",
         tags=["sounds", "kinds"],
         memory={"world": "London, Christmas morning, the 1840s", "current": "none", "places": [
             {"id": "p1", "name": "Scrooge's bedroom", "setting": "indoors", "sounds": "roomTone.houseAtNight faint"}]},
         expect=dict(place="new", setting="outdoors", main=["oldTown", "crowd", "snow"], kinds={"oldTown": ["churchBells", "villageMorning", "marketDay"]},
                     forbidden=["city", "roomTone"])),
    dict(id="cc-cratchits-quiet", book="a-christmas-carol", ch=3, at="found the mother and the children seated round the fire", n=6,
         about="back at the Cratchits', now quiet and in mourning: a known place in a new state",
         tags=["place", "state"], memory=CRATCHITS, sinceAt="found the mother and the children seated round the fire",
         expect=dict(place="p1", setting="indoors", main=["fireplace", "roomTone", "clock"], forbidden=["crowd", "murmur", "kitchen"],
                     state=["quiet", "hush", "still", "sad", "mourning", "grief", "silent"])),
    dict(id="cc-churchyard", book="a-christmas-carol", ch=3, at="lay underneath the ground", n=8,
         about="a neglected churchyard walled in by houses, at night with the last spirit",
         tags=["sounds"],
         expect=dict(place="new", setting="outdoors", main=["wind", "oldTown", "nightForest", "snow", "roomTone", "deepDrone"], forbidden=["crowd", "city", "fireplace"])),
    dict(id="cc-bells-window", book="a-christmas-carol", ch=4, at="Running to the window, he opened it, and put out his head", n=8,
         about="Christmas morning, every church bell pealing, Scrooge opens his window",
         tags=["sounds", "oneShot"], memory=SCROOGE,
         expect=dict(place="p2", setting="indoors", main=["oldTown", "roomTone", "snow"], required=["oldTown"], kinds={"oldTown": ["churchBells"]},
                     forbidden=["crowd"], transition=["windowOpens"])),
    dict(id="cc-counting-house-next-day", book="a-christmas-carol", ch=4, at="No Bob.", n=12,
         about="the day after Christmas, Scrooge in his counting-house waiting for Bob: a return to a known place",
         tags=["place", "state"], memory={"world": SCROOGE["world"], "places": SCROOGE["places"], "current": "none"},
         expect=dict(place="p1", setting="indoors", main=["roomTone", "clock", "fireplace", "oldTown"], forbidden=["crowd", "city"],
                     state=["morning", "waiting", "late", "early", "day after"])),
    # ---- The Wind in the Willows ------------------------------------------------------
    dict(id="ww-river-bank", book="wind-in-the-willows", ch=0, at="by the edge of a full-fed river", n=10,
         about="Mole comes out into the spring sunshine and reaches the river",
         tags=["sounds"],
         expect=dict(place="new", setting="outdoors", main=["river", "birdsong"], required=["river"], forbidden=["crowd", "city", "seaShore", "roomTone"])),
    dict(id="ww-boat", book="wind-in-the-willows", ch=0, at="took the sculls", n=10,
         about="Mole's first time in a rowing boat on the river",
         tags=["sounds"],
         memory={"world": "the English river bank, Edwardian; animals who live like people", "current": "p1", "places": [
             {"id": "p1", "name": "the river bank", "setting": "outdoors", "sounds": "river soft, birdsong faint", "state": "a spring morning"}]},
         expect=dict(place="any", main=["river", "openSea"], kinds={"openSea": ["rowingBoat"]}, forbidden=["seaShore", "city", "crowd"])),
    dict(id="ww-poop-poop", book="wind-in-the-willows", ch=1, at="Poop-poop!", n=10, hit=1,
         about="the caravan on the open road; a motor-car comes up behind, horn sounding",
         tags=["oneShot", "sounds"],
         memory={"world": "the English countryside, Edwardian", "current": "p1", "places": [
             {"id": "p1", "name": "the open road with Toad's gipsy caravan", "setting": "vehicle", "sounds": "horses.wagonTrain soft, birdsong faint", "state": "a golden afternoon"}]},
         expect=dict(place="p1", oneShot="carHorn", main=["horses", "birdsong", "wind", "motorVehicle"], forbidden=["city", "crowd"])),
    dict(id="ww-wild-wood-snow", book="wind-in-the-willows", ch=2, at="the snow", n=10,
         about="lost in the Wild Wood at dusk as the snow begins",
         tags=["sounds", "state"],
         memory={"world": "the English river bank, Edwardian; midwinter", "current": "p1", "places": [
             {"id": "p1", "name": "the Wild Wood", "setting": "outdoors", "sounds": "nightForest soft, wind faint", "state": "dusk, fear, pattering of feet"}]},
         expect=dict(place="p1", setting="outdoors", main=["snow", "nightForest", "wind", "forest"], forbidden=["crowd", "city", "roomTone", "birdsong"])),
    dict(id="ww-badger-kitchen", book="wind-in-the-willows", ch=3, at="the kitchen", n=10,
         about="in from the snow into Badger's warm kitchen",
         tags=["sounds", "transition"],
         memory={"world": "the English river bank, Edwardian; midwinter, snow", "current": "p1", "places": [
             {"id": "p1", "name": "the Wild Wood", "setting": "outdoors", "sounds": "snow soft, nightForest faint", "state": "night, deep snow"}]},
         expect=dict(place="new", setting="indoors", main=["fireplace", "kitchen", "roomTone"], forbidden=["crowd", "city", "snow", "nightForest"],
                     transition=["stepInside", "enterThroughDoor", "none"])),
    dict(id="ww-dungeon", book="wind-in-the-willows", ch=5, at="dungeon", n=8,
         about="Toad thrown into the castle dungeon",
         tags=["kinds"],
         expect=dict(place="new", setting="indoors", main=["dripping", "emptyHall", "roomTone"], kinds={"dripping": ["dungeon", "cave"], "emptyHall": ["prisonBlock", "castleCorridor"]},
                     forbidden=["crowd", "birdsong", "city"])),
    dict(id="ww-train", book="wind-in-the-willows", ch=7, at="engine-driver", n=10,
         about="Toad on the platform, talking to the engine-driver of a train standing in the station",
         tags=["sounds"],
         expect=dict(place="new", main=["train", "crowd", "machinery", "emptyHall"], forbidden=["city"])),
    dict(id="ww-toad-hall-banquet", book="wind-in-the-willows", ch=11, at="the banquet", n=10,
         about="in the secret tunnel under Toad Hall, the banquet roaring overhead",
         tags=["state", "sounds"], memory=TOAD_HALL,
         expect=dict(place="any", setting="indoors", main=["dripping", "murmur", "crowd", "emptyHall"], state=["banquet", "party", "feast", "guests", "dinner", "overhead", "muffled"])),
    # ---- Jane Eyre --------------------------------------------------------------------
    dict(id="je-window-seat-rain", book="jane-eyre", ch=0, at="lamentable blast", n=10,
         about="Jane in the window seat on a wet November afternoon",
         tags=["sounds"],
         expect=dict(place="new", setting="indoors", main=["rainIndoors", "roomTone", "wind"], required=["rainIndoors"], forbidden=["crowd", "city"])),
    dict(id="je-red-room", book="jane-eyre", ch=1, at="very seldom slept in", n=8,
         about="locked in the cold silent red-room",
         tags=["state"],
         expect=dict(place="new", setting="indoors", main=["roomTone", "wind", "clock"], forbidden=["crowd", "murmur", "fireplace", "city"],
                     state=["cold", "silent", "alone", "chill", "still", "dusk", "empty", "seldom"])),
    dict(id="je-lowood-schoolroom", book="jane-eyre", ch=4, at="the schoolroom was in a glorious tumult", n=10,
         about="the Lowood schoolroom between lessons, eighty girls talking at once",
         tags=["kinds"],
         expect=dict(place="any", setting="indoors", main=["crowd", "murmur"], kinds={"crowd": ["classroomChatter", "schoolyard", "cafeteria"]}, forbidden=["city", "birdsong"])),
    dict(id="je-lowood-bell", book="jane-eyre", ch=4, at="the bell rang", n=8,
         about="the school bell rings at Lowood",
         tags=["oneShot"],
         expect=dict(place="any", setting="indoors", oneShot="schoolBell")),
    dict(id="je-fairfax-parlour", book="jane-eyre", ch=10, at="the neatest imaginable little elderly lady", n=8,
         about="arriving at Thornfield at night: a snug room, a cheerful fire, Mrs Fairfax knitting",
         tags=["sounds"],
         expect=dict(place="new", setting="indoors", main=["fireplace", "clock", "roomTone"], required=["fireplace"], forbidden=["crowd", "city"])),
    dict(id="je-lane-horse", book="jane-eyre", ch=11, at="a rude noise broke on these fine ripplings and whisperings", n=10,
         about="a still frosty lane at sunset; a horse heard coming",
         tags=["sounds", "state"],
         expect=dict(place="new", setting="outdoors", main=["wind", "horses", "birdsong", "snow", "river"], forbidden=["crowd", "city"],
                     state=["winter", "cold", "frost", "evening", "sunset", "still", "january"])),
    dict(id="je-orchard-rain-rushes", book="jane-eyre", ch=22, at="the rain rushed down", n=10,
         about="the storm breaks over the orchard at Thornfield",
         tags=["transition"], sinceAt="The rain rushed down",
         memory={"world": "Thornfield Hall, the English midlands, a midsummer evening, the 1800s", "current": "p1", "places": [
             {"id": "p1", "name": "the orchard at Thornfield", "setting": "outdoors", "sounds": "nightInsects soft, wind faint", "state": "a still midsummer evening"}]},
         expect=dict(place="p1", setting="outdoors", main=["heavyRain", "rain", "strongWind", "thunder"], moment="swell", transition=["stormBreaks"])),
    dict(id="je-orchard-thunder-crack", book="jane-eyre", ch=22, at="close rattling peal", n=10,
         about="lightning and a crack of thunder over the orchard",
         tags=["oneShot"],
         memory={"world": "Thornfield Hall, the English midlands, a midsummer evening, the 1800s", "current": "p1", "places": [
             {"id": "p1", "name": "the orchard at Thornfield", "setting": "outdoors", "sounds": "heavyRain full, strongWind soft", "state": "the storm breaking"}]},
         expect=dict(place="p1", setting="outdoors", oneShot="thunderClap", main=["heavyRain", "strongWind", "thunder", "rain", "wind"], since="none")),
    dict(id="je-church-hush", book="jane-eyre", ch=25, at="quiet and humble temple", n=8,
         about="walking into the quiet church for the wedding: a hush",
         tags=["transition", "kinds"], sinceAt="quiet and humble temple",
         expect=dict(place="new", setting="indoors", main=["emptyHall", "hushedRoom", "roomTone"], kinds={"emptyHall": ["cathedral", "stoneHall"], "hushedRoom": ["chapel", "monastery"]},
                     moment="hush", forbidden=["crowd", "city"], transition=["enterThroughDoor", "stepInside"])),
    dict(id="je-moor-night", book="jane-eyre", ch=27, at="warm with the heat of the summer day", n=10,
         about="Jane alone on the moor at night in summer",
         tags=["sounds", "state"],
         expect=dict(place="new", setting="outdoors", main=["nightInsects", "wind", "nightForest"], forbidden=["crowd", "city", "roomTone", "birdsong"],
                     state=["night", "summer", "dark", "evening"])),
    dict(id="je-moor-house-window", book="jane-eyre", ch=27, at="knitting a stocking", n=10,
         about="outside Moor House at night in the rain, looking in at the kitchen",
         tags=["sounds"],
         expect=dict(place="any", setting="outdoors", main=["rain", "wind", "nightInsects", "nightForest", "strongWind"], forbidden=["crowd", "city"])),
    # ---- The Secret Garden ------------------------------------------------------------
    dict(id="sg-carriage-moor", book="the-secret-garden", ch=2, at="wild, low, rushing sound", n=10,
         about="the carriage across the moor at night; wind and rain",
         tags=["sounds", "kinds"],
         expect=dict(place="any", setting="vehicle", main=["horses", "wind", "rain", "strongWind"], kinds={"horses": ["stagecoach"]}, required=["wind|strongWind"],
                     forbidden=["city", "crowd"], state=["night", "rain", "dark", "wind", "moor"])),
    dict(id="sg-arrival-hall", book="the-secret-garden", ch=2, at="It opened into an enormous hall", n=8,
         about="in from the rainy night into the manor's hall: the weather follows indoors",
         tags=["sounds", "transition"], sinceAt="It opened into an enormous hall",
         memory={"world": "the Yorkshire moor, Edwardian England; a wet night", "current": "p1", "places": [
             {"id": "p1", "name": "the carriage across the moor", "setting": "vehicle", "sounds": "horses.stagecoach soft, rain soft, wind soft", "state": "night, rain, wind"}]},
         expect=dict(place="new", setting="indoors", main=["emptyHall", "rainIndoors", "roomTone", "wind"], forbidden=["rain", "horses", "crowd", "city"],
                     transition=["stepInside", "enterThroughDoor"])),
    dict(id="sg-wuthering", book="the-secret-garden", ch=4, at="wutherin'", n=8,
         about="Martha and Mary indoors, the wind wuthering round the house",
         tags=["sounds"],
         expect=dict(place="any", setting="indoors", main=["wind", "roomTone", "strongWind", "fireplace"], required=["wind|strongWind"], forbidden=["crowd", "city"])),
    dict(id="sg-crying-corridor", book="the-secret-garden", ch=4, at="crying", n=8, hit=2,
         about="a far-off crying heard down the corridors of the manor at night",
         tags=["kinds"],
         expect=dict(place="any", setting="indoors", main=["emptyHall", "wind", "strongWind", "roomTone"], kinds={"emptyHall": ["castleCorridor", "hotelCorridor", "stoneHall"]}, forbidden=["crowd", "city"])),
    dict(id="sg-robin-garden", book="the-secret-garden", ch=8, at="the robin", n=8, hit=2,
         about="inside the secret garden for the first time, the robin singing",
         tags=["kinds"],
         expect=dict(place="any", setting="outdoors", main=["birdsong", "wind"], kinds={"birdsong": ["garden", "springMorning", "orchard"]}, forbidden=["crowd", "city", "roomTone"])),
    dict(id="sg-garden-spring", book="the-secret-garden", ch=14, at="this nest-buildin' is", n=10,
         about="the garden months later in spring, birds nesting: the same place in a new state",
         tags=["state", "place"], memory=SECRET_GARDEN_WINTER,
         expect=dict(place="p1", setting="outdoors", main=["birdsong"], state=["spring", "nest", "sun", "warm", "green", "bud"])),
    # ---- The Railway Children ---------------------------------------------------------
    dict(id="rc-nine-fifteen", book="railway-children", ch=2, at="the 9.15", n=8,
         about="the children on the fence above the line, waving to the morning train",
         tags=["sounds"],
         expect=dict(place="any", setting="outdoors", main=["birdsong", "wind", "train", "farmyard"], forbidden=["crowd", "city", "roomTone"])),
    dict(id="rc-tunnel", book="railway-children", ch=11, at="before the tunnel is quite dark", n=8,
         about="walking into the railway tunnel",
         tags=["kinds"],
         expect=dict(place="new", setting="indoors", main=["dripping", "train", "emptyHall"], kinds={"dripping": ["tunnel", "cave"]}, forbidden=["crowd", "birdsong", "city"])),
    dict(id="rc-green-dragon", book="railway-children", ch=2, at="tore shrieking out of the mouth of its dark lair", n=8,
         about="the morning express tears shrieking out of the tunnel past the children on the fence",
         tags=["sounds"],
         expect=dict(place="any", setting="outdoors", main=["train", "birdsong", "wind"], oneShot="trainWhistle|none", forbidden=["city", "crowd", "roomTone"])),
    dict(id="rc-perks-kitchen", book="railway-children", ch=9, at="buttoning her bodice", n=8,
         about="in the Perks's cottage kitchen",
         tags=["sounds"],
         expect=dict(place="any", setting="indoors", main=["kitchen", "roomTone", "murmur", "fireplace", "river"], forbidden=["crowd", "train", "city"])),
    # ---- The Call of the Wild ---------------------------------------------------------
    dict(id="cw-judge-miller", book="call-of-the-wild", ch=0, at="Judge Miller's place", n=6,
         about="Buck's home in the sun-kissed Santa Clara valley",
         tags=["sounds"],
         expect=dict(place="new", setting="outdoors", main=["birdsong", "farmyard", "river", "wind"], forbidden=["snow", "strongWind", "crowd", "city"])),
    dict(id="cw-sled-trail", book="call-of-the-wild", ch=1, at="guiding the sled at the gee-pole", n=8,
         about="the dog team pulling the sled on the frozen trail",
         tags=["kinds"],
         expect=dict(place="any", main=["horses", "snow", "wind", "strongWind"], kinds={"horses": ["dogSled"]}, forbidden=["city", "crowd", "birdsong"])),
    dict(id="cw-camp-fire", book="call-of-the-wild", ch=2, at="eat supper in the dark", n=8,
         about="the camp at night on the trail, the fire, the dogs",
         tags=["kinds"],
         expect=dict(place="any", setting="outdoors", main=["campfire", "wind", "snow", "strongWind"], required=["campfire"], forbidden=["city", "crowd", "birdsong"])),
    dict(id="cw-long-drawn-howl", book="call-of-the-wild", ch=6, at="long-drawn howl", n=8,
         about="Buck hears the call of the wild: a wolf's howl from the forest",
         tags=["oneShot"],
         expect=dict(place="any", setting="outdoors", oneShot="wolfHowl", main=["nightForest", "forest", "wind"], forbidden=["city", "crowd"])),
    # ---- The Hound of the Baskervilles ------------------------------------------------
    dict(id="hb-baker-street", book="hound-of-the-baskervilles", ch=0, at="seated at the breakfast table", n=4,
         about="Holmes at breakfast in the Baker Street sitting room",
         tags=["place", "sounds"],
         expect=dict(place="new", setting="indoors", main=["roomTone", "fireplace", "clock", "oldTown"], forbidden=["city", "crowd"])),
    dict(id="hb-baker-street-smoke", book="hound-of-the-baskervilles", ch=2, at="took me by the throat", n=8,
         about="back in the sitting room in the evening, thick with pipe smoke: a return to a known place",
         tags=["place"], memory={"world": BAKER_STREET["world"], "places": BAKER_STREET["places"], "current": "none"},
         sinceAt="My first impression as I opened the door",
         expect=dict(place="p1", setting="indoors", forbidden=["city", "crowd"])),
    dict(id="hb-train-devon", book="hound-of-the-baskervilles", ch=5, at="The journey was a swift and pleasant one", n=6,
         about="the train from Paddington to Devonshire",
         tags=["sounds"],
         expect=dict(place="new", setting="vehicle", main=["train"], forbidden=["city", "horses", "crowd"])),
    dict(id="hb-wagonette", book="hound-of-the-baskervilles", ch=5, at="wagonette", n=8,
         about="off the train at a little wayside station, the wagonette waiting outside",
         tags=["sounds"],
         expect=dict(place="new", setting="outdoors", main=["birdsong", "wind", "horses", "train", "crowd", "emptyHall"], forbidden=["city"])),
    dict(id="hb-dining-room", book="hound-of-the-baskervilles", ch=5, at="the dining-room", n=8,
         about="the gloomy dining-room of Baskerville Hall",
         tags=["state", "kinds"],
         expect=dict(place="any", setting="indoors", main=["emptyHall", "fireplace", "roomTone"], kinds={"emptyHall": ["stoneHall", "castleCorridor"]},
                     forbidden=["crowd", "city"], state=["gloom", "dim", "shadow", "dark", "silent", "dinner", "sombre", "somber"])),
    dict(id="hb-moor-moan", book="hound-of-the-baskervilles", ch=6, at="a long, low moan", n=8,
         about="on the moor, a long low moan sweeps over it",
         tags=["kinds"],
         expect=dict(place="any", setting="outdoors", main=["wind", "strongWind", "nightInsects", "birdsong"], forbidden=["crowd", "city", "roomTone"])),
    dict(id="hb-stone-hut", book="hound-of-the-baskervilles", ch=10, at="the hut", n=8, hit=2,
         about="coming up to the stone hut on the moor",
         tags=["sounds"],
         expect=dict(place="any", main=["wind", "roomTone", "strongWind"], forbidden=["crowd", "city"])),
    # ---- The War of the Worlds --------------------------------------------------------
    dict(id="wow-common-crowd", book="war-of-the-worlds", ch=2, at="perhaps twenty people", n=8, lead=6,
         about="a little crowd round the cylinder on Horsell Common",
         tags=["sounds"],
         expect=dict(place="new", setting="outdoors", main=["murmur", "crowd", "birdsong", "wind"], forbidden=["roomTone", "city"])),
    dict(id="wow-exodus", book="war-of-the-worlds", ch=16, at="six million people unarmed", n=8,
         about="the whole of London stirring and running: a vast crowd",
         tags=["sounds"],
         expect=dict(place="any", setting="outdoors", main=["crowd", "oldTown", "city"], required=["crowd"], forbidden=["roomTone", "birdsong"])),
    dict(id="wow-scullery", book="war-of-the-worlds", ch=20, at="the scullery", n=8,
         about="hiding in the scullery of the ruined house beside the Martian pit",
         tags=["state", "kinds"],
         expect=dict(place="any", setting="indoors", main=["roomTone", "dripping", "machinery", "deepDrone"], kinds={"roomTone": ["cellar", "oldHouseCreaks"]},
                     forbidden=["crowd", "city", "birdsong"], state=["dark", "silent", "hidden", "trapped", "ruin", "quiet"])),
    dict(id="wow-thunder-child", book="war-of-the-worlds", ch=16, at="Thunder Child", n=8,
         about="on the Essex shore near Tillingham, a crowd of shipping of every kind offshore",
         tags=["sounds"],
         expect=dict(place="any", setting="outdoors", main=["seaShore", "crowd", "murmur", "wind", "openSea"], forbidden=["city", "roomTone"])),
    # ---- Frankenstein -----------------------------------------------------------------
    dict(id="fr-walton-ice", book="frankenstein", ch=3, at="closed in the ship on all sides", n=8,
         about="Walton's ship surrounded by ice in a fog",
         tags=["kinds", "state"],
         expect=dict(place="new", setting="vehicle", main=["ship", "strongWind", "wind", "openSea"], kinds={"strongWind": ["arcticWind"], "openSea": ["arcticSea"]},
                     forbidden=["crowd", "city", "birdsong"], state=["ice", "fog", "cold", "arctic", "frozen", "still"])),
    dict(id="fr-creation-rain", book="frankenstein", ch=7, at="the rain pattered dismally against the panes", n=8,
         about="one in the morning in the laboratory, rain on the windows",
         tags=["sounds", "state"],
         expect=dict(place="new", setting="indoors", main=["rainIndoors", "roomTone"], required=["rainIndoors"], forbidden=["crowd", "city"],
                     state=["night", "rain", "morning", "dreary", "dark", "late"])),
    dict(id="fr-montanvert", book="frankenstein", ch=13, at="I descended upon the glacier", n=8,
         about="climbing to the glacier at Montanvert",
         tags=["kinds"],
         expect=dict(place="any", setting="outdoors", main=["wind", "river", "strongWind", "birdsong"], kinds={"wind": ["mountainWind"], "river": ["mountainStream", "waterfall", "rapids"]},
                     forbidden=["crowd", "city", "roomTone"])),
    dict(id="fr-hovel", book="frankenstein", ch=14, at="reside in this hovel", n=8,
         about="the creature in his hovel beside the cottage, the family heard through the wall",
         tags=["kinds"],
         expect=dict(place="any", setting="indoors", main=["murmur", "wind", "roomTone", "fireplace", "farmyard"], kinds={"murmur": ["voicesNextRoom", "quietConversation"]},
                     forbidden=["crowd", "city"])),
    dict(id="fr-orkney", book="frankenstein", ch=22, at="three miserable huts", n=8,
         about="a hut on a remote island in the Orkneys",
         tags=["sounds"],
         expect=dict(place="any", main=["seaShore", "wind", "strongWind"], forbidden=["crowd", "city", "birdsong"])),
    dict(id="fr-thunder-crash", book="frankenstein", ch=10, at="terrific crash over my head", n=8,
         about="a storm over Geneva at night, lightning and a crash of thunder",
         tags=["oneShot"],
         expect=dict(place="any", setting="outdoors", oneShot="thunderClap", main=["heavyRain", "thunder", "strongWind", "wind", "rain"], forbidden=["crowd", "city"])),
    # ---- Wuthering Heights ------------------------------------------------------------
    dict(id="wh-hearth-dogs", book="wuthering-heights", ch=0, at="bitch pointer", n=8,
         about="Lockwood left alone by the hearth at Wuthering Heights with the dogs",
         tags=["sounds"],
         expect=dict(place="any", setting="indoors", main=["fireplace", "roomTone", "wind"], forbidden=["crowd", "city"])),
    dict(id="wh-snow-shower", book="wuthering-heights", ch=1, at="feathery flakes", n=8,
         about="walking to the Heights as the first snow begins",
         tags=["sounds"],
         expect=dict(place="any", setting="outdoors", main=["wind", "snow", "strongWind"], forbidden=["crowd", "city", "roomTone"])),
    dict(id="wh-fir-bough", book="wuthering-heights", ch=2, at="rattled its dry cones against the panes", n=8,
         about="in bed in the oak closet at night, the wind and a fir branch at the window",
         tags=["oneShot", "sounds"],
         expect=dict(place="any", setting="indoors", main=["strongWind", "wind", "roomTone", "snow"], forbidden=["crowd", "city"],
                     state=["night", "wind", "storm", "dark", "dream"])),
    dict(id="wh-storm-fury", book="wuthering-heights", ch=8, at="in full fury", n=8,
         about="midnight at the Heights, the storm comes rattling over in full fury",
         tags=["transition"], sinceAt="About midnight, while we still sat up",
         expect=dict(place="any", main=["strongWind", "thunder", "rainIndoors", "heavyRain", "wind"], moment="swell", transition=["stormBreaks"])),
    # ---- Alice's Adventures in Wonderland ---------------------------------------------
    dict(id="al-rabbit-hole", book="alice-in-wonderland", ch=0, at="Down, down, down", n=8,
         about="Alice falling slowly down the well",
         tags=["sounds"],
         expect=dict(place="any", main=["deepDrone", "roomTone", "wind", "dripping"], forbidden=["crowd", "city", "birdsong"], heard=False)),
    dict(id="al-tea-party", book="alice-in-wonderland", ch=6, at="under a tree in front of the house", n=4,
         about="the tea party at a table under a tree",
         tags=["sounds"],
         expect=dict(place="new", setting="outdoors", main=["birdsong", "murmur", "wind"], kinds={"birdsong": ["garden", "summerMeadow"]}, forbidden=["crowd", "city", "roomTone"])),
    dict(id="al-croquet", book="alice-in-wonderland", ch=7, at="such a curious croquet-ground", n=8,
         about="the Queen's croquet-ground full of courtiers",
         tags=["kinds"],
         expect=dict(place="any", setting="outdoors", main=["crowd", "murmur", "birdsong"], kinds={"crowd": ["gardenParty"]}, forbidden=["city", "roomTone"])),
    dict(id="al-trial", book="alice-in-wonderland", ch=10, at="were seated on their throne", n=6, lead=4,
         about="the court assembled for the trial of the Knave",
         tags=["kinds"],
         expect=dict(place="new", setting="indoors", main=["hushedRoom", "crowd", "murmur"], kinds={"hushedRoom": ["courtroom"], "crowd": ["courtroomGallery"]}, forbidden=["city", "birdsong"])),
    # ---- Pride and Prejudice ----------------------------------------------------------
    dict(id="pp-longbourn", book="pride-and-prejudice", ch=0, at="said his lady to him one day", n=4,
         about="Mr and Mrs Bennet at home at Longbourn",
         tags=["place"],
         expect=dict(place="new", setting="indoors", main=["roomTone", "clock", "fireplace", "murmur"], forbidden=["crowd", "city", "birdsong"])),
    dict(id="pp-assembly", book="pride-and-prejudice", ch=2, at="entered the assembly room", n=8,
         about="walking into the Meryton assembly ball",
         tags=["transition", "kinds"], sinceAt="And when the party entered the assembly room",
         expect=dict(place="new", setting="indoors", main=["crowd"], kinds={"crowd": ["ballroom", "partyIndoors"]}, moment="swell", forbidden=["city", "roomTone"],
                     transition=["enterThroughDoor", "stepInside"])),
    dict(id="pp-netherfield-ball", book="pride-and-prejudice", ch=17, at="cluster of red coats", n=6, lead=5,
         about="the Netherfield ball, the drawing-room full of officers",
         tags=["kinds"],
         expect=dict(place="any", setting="indoors", main=["crowd", "murmur"], kinds={"crowd": ["ballroom", "partyIndoors"]}, forbidden=["city", "roomTone"])),
    dict(id="pp-pemberley", book="pride-and-prejudice", ch=42, at="Pemberley Woods", n=6, lead=5,
         about="driving through the woods of Pemberley park",
         tags=["sounds"],
         expect=dict(place="any", main=["horses", "forest", "birdsong"], forbidden=["city", "crowd", "roomTone"])),
    # ---- Anne of Green Gables ---------------------------------------------------------
    dict(id="ag-rachel-window", book="anne-of-green-gables", ch=0, at="sitting at her window", n=6,
         about="Mrs Rachel Lynde at her kitchen window on a June afternoon",
         tags=["sounds"],
         expect=dict(place="new", setting="indoors", main=["roomTone", "birdsong", "kitchen", "clock"], forbidden=["crowd", "city"])),
    dict(id="ag-bright-river", book="anne-of-green-gables", ch=1, at="Bright River", n=8, hit=2,
         about="the little station at Bright River, nobody about, a girl waiting",
         tags=["sounds"],
         expect=dict(place="any", setting="outdoors", main=["birdsong", "wind", "emptyHall", "farmyard"], forbidden=["crowd", "city"])),
    dict(id="ag-avenue", book="anne-of-green-gables", ch=1, at="the Avenue", n=8, hit=2,
         about="the buggy drives under the apple blossom of the Avenue",
         tags=["sounds"],
         expect=dict(place="any", setting="vehicle", main=["horses", "birdsong"], forbidden=["city", "crowd", "train"])),
    dict(id="ag-morning-east-gable", book="anne-of-green-gables", ch=3, at="broad daylight when Anne awoke", n=4, lead=5,
         about="Anne wakes in the east gable on a June morning",
         tags=["kinds", "state"],
         expect=dict(place="any", setting="indoors", main=["roomTone", "birdsong"], kinds={"roomTone": ["bedroomMorning", "houseAtNight"]},
                     forbidden=["crowd", "city"], state=["morning", "sun", "june", "daylight", "dawn"])),
    # ---- Black Beauty -----------------------------------------------------------------
    dict(id="bb-meadow", book="black-beauty", ch=0, at="a large pleasant meadow with a pond", n=2,
         about="the meadow where Black Beauty was a foal",
         tags=["kinds"],
         expect=dict(place="new", setting="outdoors", main=["birdsong", "farmyard", "wind"], kinds={"birdsong": ["summerMeadow", "garden"], "farmyard": ["cattleField", "sheepPasture", "alpinePasture"]},
                     forbidden=["city", "crowd", "oldTown"])),
    dict(id="bb-stormy-bridge", book="black-beauty", ch=11, at="the wooden bridge", n=8,
         about="the dog-cart in a storm, the river in flood at the bridge",
         tags=["state"],
         expect=dict(place="any", setting="vehicle|outdoors", main=["heavyRain", "strongWind", "river", "horses", "rain", "wind", "forest"], kinds={"river": ["rapids"]},
                     forbidden=["city", "crowd"], state=["storm", "flood", "rain", "wind", "gale"])),
    dict(id="bb-stable-fire", book="black-beauty", ch=15, at="full of smoke", n=8,
         about="the stable fills with smoke at night; horses tied in their stalls",
         tags=["sounds"],
         expect=dict(place="any", setting="indoors", main=["farmyard", "campfire", "crowd", "workshop", "roomTone", "fireplace"], kinds={"farmyard": ["stable", "barn"]}, forbidden=["city", "birdsong"])),
    dict(id="bb-cab-stand", book="black-beauty", ch=32, at="Larry's cab was standing next to ours", n=8,
         about="a London cab stand in the 1870s: horse traffic, no motor cars",
         tags=["sounds"],
         expect=dict(place="any", setting="outdoors", main=["oldTown", "horses", "crowd"], forbidden=["city", "motorVehicle"])),
    # ---- The Time Machine -------------------------------------------------------------
    dict(id="tm-dinner-fire", book="the-time-machine", ch=0, at="the fire burned brightly", n=4,
         about="the Time Traveller's guests after dinner by the fire",
         tags=["kinds"],
         expect=dict(place="new", setting="indoors", main=["fireplace", "murmur"], kinds={"murmur": ["dinnerTable", "quietConversation"]}, forbidden=["crowd", "city"])),
    dict(id="tm-morlock-well", book="the-time-machine", ch=4, at="beating of some big engine", n=8,
         about="at the mouth of a well, machinery thudding far below",
         tags=["sounds"],
         expect=dict(place="any", main=["machinery", "wind", "dripping", "birdsong"], forbidden=["crowd", "city"])),
    # ---- Silas Marner -----------------------------------------------------------------
    dict(id="sm-loom", book="silas-marner", ch=0, at="his loom", n=8,
         about="Silas at his loom in the stone cottage",
         tags=["kinds"],
         expect=dict(place="any", setting="indoors", main=["workshop", "roomTone"], kinds={"workshop": ["loom", "sewingRoom"]}, forbidden=["crowd", "city"])),
    dict(id="sm-rainbow", book="silas-marner", ch=5, at="high pitch of animation", n=6, lead=5,
         about="the Rainbow inn's parlour on a lively evening",
         tags=["kinds"],
         expect=dict(place="any", setting="indoors", main=["crowd", "murmur"], kinds={"crowd": ["tavern", "pubCrowd"], "murmur": ["quietBar"]}, forbidden=["city"])),
    dict(id="sm-red-house-dance", book="silas-marner", ch=10, at="Solomon", n=8,
         about="the New Year's dance at the Red House, the fiddler playing",
         tags=["kinds"],
         expect=dict(place="any", setting="indoors", main=["crowd", "murmur"], kinds={"crowd": ["ballroom", "partyIndoors", "feastHall"]}, forbidden=["city"])),
]


def sentences_of(book):
    return [(ci, [s for p in ch["paragraphs"] for s in p]) for ci, ch in enumerate(book["chapters"])]


def find(chapters, at, ch=None, hit=1):
    seen = 0
    for ci, sents in chapters:
        if ch is not None and ci != ch:
            continue
        for si, s in enumerate(sents):
            if at.lower() in s.lower():
                seen += 1
                if seen == hit:
                    return ci, si, sents
    return None


def main() -> None:
    check_only = "--check" in sys.argv
    catalog = json.load(open(CATALOG, encoding="utf-8"))
    families = {s["id"] for s in catalog["sounds"]}
    kinds_of = {}
    for v in catalog["variants"]:
        kinds_of.setdefault(v["of"], set()).add(v["id"])
    one_shots = {o["id"] for o in catalog["oneShots"]} | {"none"}
    transitions = {t["id"] if isinstance(t, dict) else t for t in catalog.get("transitions", [])} | {"none"}
    books = {}
    out = []
    problems = 0
    for case in CASES:
        slug = case["book"]
        if slug not in books:
            path = BOOKS / f"{slug}.json"
            if not path.exists():
                sys.exit(f"{path} is missing: run Tools/data/fetch_books.py {slug} and make_readaloud.py {slug}")
            books[slug] = sentences_of(json.load(open(path, encoding="utf-8")))
        found = find(books[slug], case["at"], case.get("ch"), case.get("hit", 1))
        if not found:
            print(f"NO HIT  {case['id']}: {slug} ch{case.get('ch')} \"{case['at']}\"")
            problems += 1
            continue
        ci, si, sents = found
        n = case.get("n", 12)
        start = max(0, si - n + 1)
        chapters = [sents[start:si + 1]]
        if case.get("lead") and start == 0 and ci > 0:
            # A short chapter start: show the end of the previous chapter too.
            previous = books[slug][ci - 1][1]
            chapters = [previous[-case["lead"]:]] + chapters
        if case.get("extra"):
            chapters.append(case["extra"])
        memory = case.get("memory")
        expect = dict(case["expect"])
        if case.get("sinceAt"):
            where = [i for i, s in enumerate(chapters[-1]) if case["sinceAt"].lower() in s.lower()]
            if not where:
                print(f"NO SINCE  {case['id']}: \"{case['sinceAt']}\" is not in the passage")
                problems += 1
            else:
                expect["since"] = " ".join(chapters[-1][where[-1]].split()[:6])
        for label in ("main", "required", "forbidden"):
            for family in [f for item in (expect.get(label) or []) for f in item.split("|")]:
                if family not in families:
                    print(f"BAD FAMILY  {case['id']}: {family}")
                    problems += 1
        for family, accepted in (expect.get("kinds") or {}).items():
            for kind in accepted:
                if kind not in kinds_of.get(family, set()):
                    print(f"BAD KIND  {case['id']}: {family}.{kind}")
                    problems += 1
        for sound in (expect.get("oneShot") or "").split("|"):
            if sound and sound not in one_shots:
                print(f"BAD ONE-OFF  {case['id']}: {sound}")
                problems += 1
        for t in expect.get("transition") or []:
            if t not in transitions:
                print(f"BAD TRANSITION  {case['id']}: {t}")
                problems += 1
        if any(x not in ("indoors", "outdoors", "vehicle") for x in (expect.get("setting") or "indoors").split("|")) \
                or any(x not in ("none", "swell", "hush") for x in (expect.get("moment") or "none").split("|")):
            print(f"BAD SETTING/MOMENT  {case['id']}")
            problems += 1
        if memory and expect["place"] not in ("new", "none", "any") and expect["place"] not in {p["id"] for p in memory["places"]}:
            print(f"BAD PLACE  {case['id']}: expected {expect['place']} is not in the memory")
            problems += 1
        item = {"id": case["id"], "book": slug, "about": case.get("about"), "tags": case.get("tags"), "chapters": chapters, "expect": expect}
        if memory:
            item["memory"] = memory
        words = sum(len(s.split()) for c in chapters for s in c)
        if not check_only:
            last = chapters[-1][-1]
            print(f"{case['id']:28} ch{ci} s{si} {words:4d}w  ...{last[-110:]}")
        out.append(item)
    if problems:
        print(f"{problems} problem(s)")
    if not check_only:
        with open(OUT, "w", encoding="utf-8") as f:
            for item in out:
                f.write(json.dumps(item, ensure_ascii=False) + "\n")
        print(f"wrote {len(out)} cases to {OUT}")


if __name__ == "__main__":
    main()
