import Foundation

/// The catalogue of sounds the scorer may use: every built-in sound family
/// (``AmbientSound``), the more specific kinds of each (the starter ``SoundVariant``s,
/// fetched for every book), and a guide to what common places sound like and how they
/// change with what is going on there.
///
/// It is the one source of truth. The scorer's system prompt is made from it, the CLI
/// exports it (`lofi-atmosphere catalog`) as `Tools/atmosphere/catalog.json`, which the
/// fetch script reads for its search words, and a test keeps that file in step with
/// this one. A variant's recordings live in `Atmosphere/<Family>.<Variant>/`; until they
/// are imported the family's own recording plays, so nothing here needs a recording to
/// be there.
public enum SoundCatalog {
    /// Bump when entries change in a way the fetch script should notice.
    public static let version = 3

    /// A more specific kind of a built-in sound.
    public struct Variant: Sendable, Hashable {
        public var id: String
        public var of: AmbientSound
        /// What it is, for the scorer and the credits, up to about ten words.
        public var about: String
        /// Words to search a sound library with, best first.
        public var searches: [String]

        public init(_ id: String, _ of: AmbientSound, _ about: String, _ searches: [String]) {
            self.id = id
            self.of = of
            self.about = about
            self.searches = searches
        }

        public var variant: SoundVariant {
            SoundVariant(id: id, of: of, about: about, search: searches.first ?? about)
        }

        public var folderName: String { SoundVariant.folderName(of: of, id: id) }
    }

    /// What a kind of place sounds like, and how that changes with its state.
    public struct PlaceGuide: Sendable, Hashable {
        public struct State: Sendable, Hashable {
            /// When: "between lessons", "after hours".
            public var when: String
            /// The sounds then, as "sound.variant level, ...".
            public var sounds: String

            public init(_ when: String, _ sounds: String) {
                self.when = when
                self.sounds = sounds
            }
        }

        public var place: String
        public var states: [State]

        public init(_ place: String, _ states: [State]) {
            self.place = place
            self.states = states
        }
    }

    // MARK: - The variants

    public static let variants: [Variant] = [
        // Weather
        .init("drizzle", .rain, "a light drizzle, barely there", ["light drizzle rain", "drizzle ambience"]),
        .init("rainOnLeaves", .rain, "rain falling through a forest canopy", ["rain forest leaves", "rain on leaves"]),
        .init("rainyStreet", .rain, "rain on a pavement or street, puddles", ["rain street ambience", "rain on pavement"]),
        .init("rainOnUmbrella", .rain, "walking under an umbrella in the rain", ["rain on umbrella", "umbrella rain walking"]),
        .init("rainInGarden", .rain, "rain in a garden or yard, on plants and paving", ["rain garden ambience", "rain backyard"]),
        .init("monsoon", .heavyRain, "monsoon rain, warm and relentless", ["monsoon rain", "tropical heavy rain"]),
        .init("tropicalStorm", .heavyRain, "a tropical storm: driving rain and wind", ["tropical storm rain wind", "hurricane rain"]),
        .init("tentRain", .rainIndoors, "rain drumming on a tent", ["rain on tent", "rain tent canvas"]),
        .init("rainOnTinRoof", .rainIndoors, "rain on a tin or metal roof", ["rain on tin roof", "rain metal roof"]),
        .init("rainOnCarRoof", .rainIndoors, "rain on the roof of a parked car", ["rain on car roof", "rain inside car"]),
        .init("rainOnWindowNight", .rainIndoors, "rain on a window at night, the room quiet", ["rain on window night", "rain window interior night"]),
        .init("blizzard", .strongWind, "a blizzard of driving snow and wind", ["blizzard wind snow", "blizzard ambience"]),
        .init("sandstorm", .strongWind, "a sandstorm or dust storm", ["sandstorm wind", "desert dust storm wind"]),
        .init("hurricane", .strongWind, "a hurricane or typhoon at its height", ["hurricane wind", "typhoon wind howling"]),
        .init("moorGale", .strongWind, "a gale over open moorland or heath", ["moor wind gale", "windy moor ambience"]),
        .init("arcticWind", .strongWind, "polar wind over ice and snow", ["arctic wind", "polar wind ice"]),
        .init("desertWind", .wind, "wind blowing over sand in a desert", ["desert wind", "desert wind ambience"]),
        .init("mountainWind", .wind, "wind on a high mountain ridge", ["mountain wind", "mountain top wind"]),
        .init("windChimes", .wind, "a breeze with wind chimes on a porch", ["wind chimes breeze", "wind chimes ambience"]),
        .init("windInTallGrass", .wind, "wind through tall grass, a wheat field, a prairie", ["wind grass field", "wind in tall grass"]),
        .init("windInPines", .wind, "wind sighing through pine trees", ["wind in pines", "wind through pine trees"]),
        .init("ruins", .wind, "wind through ruins or an abandoned building", ["wind ruins ambience", "wind abandoned building"]),
        .init("battlements", .wind, "wind on castle walls or a high tower", ["wind castle walls", "wind tower high"]),
        .init("seaBreeze", .wind, "a sea breeze through palms or dune grass", ["sea breeze palms", "wind palm trees beach"]),
        .init("tentWind", .wind, "wind against a tent's canvas", ["wind tent canvas", "wind flapping tent"]),
        .init("snowfallNight", .snow, "snow falling at night, utterly still", ["snow falling night quiet", "snowfall ambience quiet"]),
        .init("snowyForest", .snow, "a snowy forest, muffled, a branch dropping snow", ["snowy forest ambience", "winter forest snow quiet"]),
        .init("distantStorm", .thunder, "a storm far off, rumbling now and then", ["distant thunder rumble", "far thunder storm"]),
        // Fire
        .init("woodStove", .fireplace, "a wood stove burning, its iron ticking", ["wood stove burning", "wood burning stove crackle"]),
        .init("dyingEmbers", .fireplace, "a fire burned down to embers, soft", ["embers fire crackling soft", "fire embers glowing"]),
        .init("bonfire", .campfire, "a big roaring bonfire", ["bonfire roaring", "large bonfire crackling"]),
        .init("torches", .campfire, "torches flickering in a passage or hall", ["torch flame flicker", "fire torch burning"]),
        .init("campAtNight", .campfire, "a campfire at night with crickets around", ["campfire night crickets", "campfire ambience night"]),
        // Water
        .init("tropicalBeach", .seaShore, "a tropical beach: gentle waves, palms", ["tropical beach waves", "beach waves palms"]),
        .init("stormySea", .seaShore, "waves crashing on rocks in a storm", ["stormy sea waves crashing rocks", "storm waves cliffs"]),
        .init("cliffs", .seaShore, "a cliff top: waves far below, wind, gulls", ["cliff top waves wind gulls", "sea cliffs ambience"]),
        .init("pier", .seaShore, "a pier or jetty: water under the boards, gulls", ["pier ambience waves gulls", "jetty water boards"]),
        .init("estuary", .seaShore, "an estuary or mudflats: wading birds, lapping water", ["estuary birds ambience", "mudflats birds water"]),
        .init("beachNight", .seaShore, "a beach at night, waves in the dark", ["beach night waves", "ocean waves night"]),
        .init("pebbleBeach", .seaShore, "waves dragging over a pebble beach", ["pebble beach waves", "shingle beach waves"]),
        .init("lakeShore", .seaShore, "small waves lapping a lake shore", ["lake shore lapping water", "lake waves lapping"]),
        .init("harbour", .seaShore, "a harbour: water against the quay, gulls, rigging", ["harbour ambience gulls", "harbor boats rigging"]),
        .init("underwater", .openSea, "under water, muffled and deep", ["underwater ambience", "underwater bubbles ambience"]),
        .init("rowingBoat", .openSea, "a small rowing boat on calm water", ["rowing boat oars water", "rowboat oars lake"]),
        .init("ferry", .openSea, "a ferry crossing: engine, water, wind on deck", ["ferry deck ambience", "ferry engine water"]),
        .init("motorboat", .openSea, "a motorboat under way", ["motorboat engine water", "speedboat ambience"]),
        .init("narrowboat", .openSea, "a canal boat or barge, slow engine, still water", ["canal boat engine", "narrowboat ambience"]),
        .init("arcticSea", .openSea, "a cold sea with ice creaking and knocking", ["sea ice creaking", "arctic sea ice ambience"]),
        .init("calmNightSea", .openSea, "a calm sea at night, water lapping the hull", ["boat night water lapping hull", "calm sea night boat"]),
        .init("waterfall", .river, "a waterfall close by", ["waterfall", "waterfall ambience"]),
        .init("fountain", .river, "a fountain splashing in a courtyard", ["fountain courtyard", "fountain water splashing"]),
        .init("runningTap", .river, "a tap running into a basin", ["running tap water sink", "faucet running water"]),
        .init("mountainStream", .river, "a fast cold mountain stream", ["mountain stream", "alpine stream water"]),
        .init("rapids", .river, "river rapids, roaring white water", ["river rapids", "white water rapids"]),
        .init("canal", .river, "a canal or slow river: still water, a lock", ["canal water ambience", "slow river ambience"]),
        .init("jungleRiver", .river, "a jungle river with birds and insects", ["jungle river ambience", "rainforest river"]),
        .init("hotSpring", .river, "a hot spring bubbling and steaming", ["hot spring bubbling", "thermal spring water"]),
        .init("shower", .river, "a shower running", ["shower running water", "shower ambience bathroom"]),
        .init("bathFilling", .river, "a bath filling", ["bath filling water", "bathtub filling"]),
        .init("millWheel", .river, "a water mill: the wheel turning, water pouring", ["water mill wheel", "watermill ambience"]),
        .init("cave", .dripping, "a cave: drips, a far echo, still air", ["cave ambience drips", "cave interior echo"]),
        .init("dungeon", .dripping, "a dungeon: drips, chains, stone", ["dungeon ambience drips", "dungeon ambience stone"]),
        .init("sewer", .dripping, "a sewer or storm drain: trickling, echo", ["sewer ambience water", "sewer tunnel dripping"]),
        .init("mine", .dripping, "a mine shaft or tunnel: drips, timbers", ["mine shaft ambience", "mine tunnel dripping"]),
        .init("crypt", .dripping, "a crypt or catacomb, still and damp", ["crypt ambience", "catacombs ambience"]),
        .init("tunnel", .dripping, "a long tunnel: distant echoes, drips", ["tunnel ambience echo", "tunnel dripping echo"]),
        .init("iceCave", .dripping, "an ice cave: drips and creaking ice", ["ice cave ambience", "glacier cave dripping"]),
        // Nature
        .init("jungle", .forest, "a tropical jungle: insects, birds, humid air", ["jungle ambience", "rainforest ambience day"]),
        .init("bambooGrove", .forest, "a bamboo grove creaking and rustling", ["bamboo forest wind", "bamboo grove ambience"]),
        .init("autumnWoods", .forest, "autumn woods: dry leaves, a crow, wind", ["autumn forest ambience", "autumn woods leaves wind"]),
        .init("pineForest", .forest, "a pine forest: wind in the needles, birds far off", ["pine forest ambience", "coniferous forest ambience"]),
        .init("summerMeadow", .birdsong, "a summer meadow: bees, grasshoppers, birds", ["summer meadow insects", "meadow ambience bees birds"]),
        .init("garden", .birdsong, "a garden by day: birds, a bee, leaves", ["garden ambience birds", "backyard birds ambience"]),
        .init("springMorning", .birdsong, "an early spring morning, birds everywhere", ["spring morning birds", "dawn chorus spring"]),
        .init("orchard", .birdsong, "an orchard or vineyard: birds, bees, a light wind", ["orchard ambience birds", "vineyard ambience"]),
        .init("savanna", .birdsong, "the African savanna by day: birds, insects, wind", ["savanna ambience", "african savanna birds"]),
        .init("alpineMeadow", .birdsong, "an alpine meadow: wind, birds, cowbells far off", ["alpine meadow cowbells", "mountain meadow ambience"]),
        .init("beehive", .birdsong, "bees humming around a hive", ["bees hive humming", "beehive ambience"]),
        .init("park", .birdsong, "a town park: birds, children far off, a distant road", ["park ambience birds", "city park ambience"]),
        .init("desertNight", .nightInsects, "a desert at night: a few insects, a thin wind", ["desert night ambience", "desert night insects"]),
        .init("tropicalNight", .nightInsects, "a tropical night: loud insects, frogs far off", ["tropical night insects", "tropical night ambience"]),
        .init("porchEvening", .nightInsects, "a porch on a summer evening: crickets, chimes", ["summer evening porch crickets", "crickets evening ambience"]),
        .init("savannaNight", .nightInsects, "the savanna at night, insects and far calls", ["savanna night ambience", "african night insects"]),
        .init("lakeNight", .nightInsects, "a lake at night: crickets, water lapping", ["lake night ambience crickets", "lakeside night"]),
        .init("jungleNight", .nightForest, "a jungle at night: insects, frogs, a call", ["jungle night ambience", "rainforest night"]),
        .init("graveyardNight", .nightForest, "a graveyard at night: wind, an owl, stillness", ["graveyard night ambience", "cemetery night wind"]),
        .init("winterNight", .nightForest, "a winter night outdoors, very still, an owl", ["winter night ambience quiet", "cold night owl"]),
        .init("mountainNight", .nightForest, "a mountain at night: wind, a far animal", ["mountain night ambience", "mountain night wind"]),
        .init("duckPond", .swamp, "a pond with ducks and geese", ["pond ducks ambience", "duck pond"]),
        .init("ricePaddy", .swamp, "rice paddies: frogs, water, birds", ["rice paddy frogs", "rice field ambience"]),
        .init("mangrove", .swamp, "a mangrove or bayou: insects, water, birds", ["mangrove ambience", "bayou ambience"]),
        .init("reedBed", .swamp, "reed beds in the wind, water birds", ["reeds wind birds", "reed bed ambience"]),
        .init("barn", .farmyard, "inside a barn: animals shifting, straw, a breeze", ["barn ambience animals", "barn interior cows"]),
        .init("stable", .farmyard, "a stable: horses shifting, snorting, straw", ["stable horses ambience", "horse stable interior"]),
        .init("henhouse", .farmyard, "hens clucking in a yard or henhouse", ["chickens clucking", "hens farmyard"]),
        .init("sheepPasture", .farmyard, "sheep on a hillside, bleating now and then", ["sheep field bleating", "sheep pasture ambience"]),
        .init("cattleField", .farmyard, "cattle in a field, lowing, grazing", ["cows field ambience", "cattle lowing field"]),
        .init("alpinePasture", .farmyard, "an alpine pasture: cowbells, wind", ["cowbells alpine", "cow bells pasture"]),
        .init("kennels", .farmyard, "dogs in kennels or a yard, barking far off", ["dogs kennel ambience", "dogs barking distant"]),
        // Rooms
        .init("houseAtNight", .roomTone, "a house at night: the fridge, a creak, silence", ["house at night ambience", "quiet house night room tone"]),
        .init("oldHouseCreaks", .roomTone, "an old house creaking, wind in the chimney", ["old house creaking", "haunted house ambience creaks"]),
        .init("attic", .roomTone, "an attic: wind under the eaves, timbers", ["attic ambience", "attic wind creaks"]),
        .init("cellar", .roomTone, "a cellar: damp, still, a far drip", ["cellar ambience", "basement quiet ambience"]),
        .init("hotelRoom", .roomTone, "a hotel room: hum, the city muffled", ["hotel room ambience", "hotel room tone"]),
        .init("bedroomMorning", .roomTone, "a bedroom in the morning, birds outside", ["bedroom morning ambience", "morning room birds window"]),
        .init("classroomEmpty", .roomTone, "an empty classroom: lights hum, the hallway far off", ["empty classroom ambience", "classroom room tone"]),
        .init("officeAfterHours", .roomTone, "an office after hours, lights and a fan", ["empty office night ambience", "office after hours"]),
        .init("cabinInterior", .roomTone, "a log cabin: timbers, wind outside", ["cabin interior ambience", "log cabin ambience wind"]),
        .init("castleChamber", .roomTone, "a stone chamber: still, cold, a draught", ["castle room ambience", "stone room ambience"]),
        .init("carriageInterior", .roomTone, "inside a stationary carriage or coach", ["carriage interior creaks", "coach interior ambience"]),
        .init("library", .hushedRoom, "a hushed library: pages turning, soft footsteps", ["library ambience quiet", "library pages turning"]),
        .init("classroomQuiet", .hushedRoom, "a classroom at work: pens, a cough, a chair", ["classroom quiet writing", "classroom ambience students writing"]),
        .init("examHall", .hushedRoom, "an exam hall: pens scratching, a clock", ["exam hall ambience", "exam room writing quiet"]),
        .init("studyHall", .hushedRoom, "a study hall or reading room", ["reading room ambience", "study hall quiet"]),
        .init("chapel", .hushedRoom, "a chapel or church with a few people, hushed", ["church interior quiet", "chapel ambience quiet"]),
        .init("courtroom", .hushedRoom, "a courtroom in session: creaks, papers, a cough", ["courtroom ambience", "courtroom quiet"]),
        .init("officeQuiet", .hushedRoom, "a quiet office: keyboards, a phone far off", ["office ambience keyboards", "quiet office typing"]),
        .init("typewriter", .hushedRoom, "a typewriter clacking in a quiet room", ["typewriter typing", "typewriter ambience"]),
        .init("monastery", .hushedRoom, "a monastery: stone, sandals, a far bell", ["monastery ambience", "cloister ambience"]),
        .init("theatreAudience", .hushedRoom, "an audience in the dark: a cough, a creak", ["theater audience quiet", "audience silence coughs"]),
        .init("bookshop", .hushedRoom, "a bookshop: pages, a till, soft steps", ["bookshop ambience", "bookstore ambience"]),
        .init("museum", .hushedRoom, "a museum gallery: footsteps, hush", ["museum ambience", "museum gallery footsteps"]),
        .init("artStudio", .hushedRoom, "a studio: brushes, a radio off, a window open", ["art studio ambience", "painting studio quiet"]),
        .init("whispers", .murmur, "people whispering around the characters", ["people whispering ambience", "whispering crowd"]),
        .init("hallwayWhispers", .murmur, "a corridor where people whisper and glance as you pass", ["hallway whispering", "school hallway whispers"]),
        .init("quietConversation", .murmur, "one quiet conversation at the next table", ["quiet conversation restaurant", "two people talking distant"]),
        .init("voicesNextRoom", .murmur, "voices muffled through a wall or door", ["muffled voices next room", "voices through wall"]),
        .init("waitingRoom", .murmur, "a waiting room: a few low voices, a cough", ["waiting room ambience", "doctor waiting room"]),
        .init("dinnerTable", .murmur, "a family meal: cutlery, low talk", ["dinner table ambience", "family dinner cutlery"]),
        .init("dormitoryNight", .murmur, "a dormitory at night: whispers in the dark", ["dormitory night whispers", "bedroom whispering night"]),
        .init("classroomWhispers", .murmur, "pupils whispering while the teacher is out", ["classroom whispering students", "classroom chatter quiet"]),
        .init("quietBar", .murmur, "a near-empty bar: a few voices, glasses", ["quiet bar ambience", "empty bar ambience"]),
        .init("hospitalRoom", .murmur, "a hospital room: low voices, a monitor", ["hospital room ambience", "hospital ward quiet voices"]),
        .init("smallShop", .murmur, "a small shop: a customer, a till, the door", ["small shop ambience", "store ambience quiet"]),
        .init("backstage", .murmur, "backstage: hushed voices, the hall beyond", ["backstage ambience", "theater backstage"]),
        .init("schoolHallwayEmpty", .emptyHall, "a school corridor after hours: lockers, far steps", ["empty school hallway", "school corridor empty"]),
        .init("hospitalCorridor", .emptyHall, "a hospital corridor: far trolleys, a door, hum", ["hospital corridor ambience", "hospital hallway"]),
        .init("castleCorridor", .emptyHall, "a stone corridor: echo, a draught", ["castle corridor ambience", "stone hallway echo"]),
        .init("stairwell", .emptyHall, "a stairwell: footsteps and doors echoing", ["stairwell ambience", "stairwell echo footsteps"]),
        .init("cathedral", .emptyHall, "a cathedral: a vast hush, far footsteps", ["cathedral ambience", "cathedral interior reverb"]),
        .init("parkingGarage", .emptyHall, "a parking garage: echo, a distant car", ["parking garage ambience", "underground car park"]),
        .init("prisonBlock", .emptyHall, "a cell block: echoes, far clangs, a voice", ["prison ambience", "prison cell block"]),
        .init("stoneHall", .emptyHall, "a great hall, empty: echo, a fire far off", ["great hall ambience empty", "large stone hall reverb"]),
        .init("warehouse", .emptyHall, "a warehouse: vast, a fan, far clatter", ["warehouse ambience", "warehouse interior"]),
        .init("hangar", .emptyHall, "a hangar or vast shed", ["hangar ambience", "aircraft hangar interior"]),
        .init("lobbyNight", .emptyHall, "a lobby at night, nearly empty", ["lobby ambience night", "empty lobby ambience"]),
        .init("hotelCorridor", .emptyHall, "a hotel corridor: carpet, a far lift, doors", ["hotel corridor ambience", "hotel hallway"]),
        .init("emptyStation", .emptyHall, "a station at night, nearly empty", ["empty train station night", "station ambience night"]),
        .init("office", .electricHum, "a quiet office: air conditioning, distant keyboards", ["office ambience", "office room tone air conditioning"]),
        .init("hospitalWard", .electricHum, "a hospital ward: monitors, hum, far voices", ["hospital ward ambience", "hospital monitor beeping ambience"]),
        .init("hospitalNight", .electricHum, "a hospital at night: a monitor, hum, a far cart", ["hospital night ambience", "hospital room night monitor"]),
        .init("serverRoom", .electricHum, "a server room or control room: fans, hum", ["server room ambience", "computer room fans"]),
        .init("laboratory", .electricHum, "a laboratory: hum, a fridge, glass", ["laboratory ambience", "science lab ambience"]),
        .init("basement", .electricHum, "a basement: a boiler, pipes, hum", ["basement ambience boiler", "basement hum pipes"]),
        .init("lateNightDiner", .electricHum, "a diner late at night: a fridge, a fan, a cup", ["diner ambience night", "late night diner"]),
        .init("bunker", .electricHum, "a bunker or shelter: ventilation, close walls", ["bunker ambience", "shelter ventilation hum"]),
        .init("radioStatic", .electricHum, "radio static between stations", ["radio static", "radio static hiss"]),
        .init("fridgeAtNight", .electricHum, "a kitchen at night, the fridge humming", ["refrigerator hum", "fridge humming kitchen night"]),
        .init("neonBuzz", .electricHum, "a neon sign buzzing", ["neon sign buzz", "neon light hum"]),
        .init("submarine", .electricHum, "inside a submarine: hum, a ping, creaks", ["submarine interior ambience", "submarine sonar ambience"]),
        .init("elevator", .electricHum, "inside a lift: hum, cables", ["elevator interior ambience", "lift ride hum"]),
        .init("homeKitchen", .kitchen, "a home kitchen: a kettle, a sizzle, dishes", ["kitchen ambience cooking", "home kitchen breakfast cooking"]),
        .init("restaurantKitchen", .kitchen, "a restaurant kitchen at full tilt", ["restaurant kitchen ambience", "busy kitchen ambience"]),
        .init("campCooking", .kitchen, "cooking over a camp fire", ["campfire cooking", "camp cooking fire pot"]),
        .init("shipsGalley", .kitchen, "a ship's galley: pots, creaks", ["ship galley ambience", "kitchen boat ambience"]),
        .init("dishwashing", .kitchen, "washing up: water, plates, cutlery", ["washing dishes", "dishwashing sink"]),
        .init("bakery", .kitchen, "a bakery: ovens, trays, flour", ["bakery ambience", "bakery kitchen"]),
        .init("blacksmith", .workshop, "a smithy: the forge roaring, hammer on iron", ["blacksmith forge", "blacksmith hammering anvil"]),
        .init("carpentry", .workshop, "a carpenter's shop: saw, plane, chisel", ["carpentry workshop", "woodworking workshop ambience"]),
        .init("sewingRoom", .workshop, "a sewing room: a machine, scissors", ["sewing machine", "sewing room ambience"]),
        .init("printingShop", .workshop, "a printing shop: the press, paper", ["printing press", "print shop ambience"]),
        .init("garage", .workshop, "a mechanic's garage: tools, a compressor", ["mechanic garage ambience", "auto repair shop"]),
        .init("loom", .workshop, "a loom or spinning wheel at work", ["loom weaving", "weaving loom ambience"]),
        .init("pottery", .workshop, "a potter's wheel, clay and water", ["pottery wheel", "potter wheel ambience"]),
        .init("shipyard", .workshop, "a shipyard or dock: hammering, gulls, water", ["shipyard ambience", "dockyard hammering"]),
        // People
        .init("cafe", .crowd, "a cafe: low chatter, cups and saucers", ["cafe ambience", "coffee shop ambience"]),
        .init("tavern", .crowd, "a busy tavern or pub: murmur, mugs, laughter", ["tavern pub ambience", "medieval tavern ambience"]),
        .init("marketplace", .crowd, "an open-air market: stalls, chatter, footsteps", ["market ambience", "outdoor market crowd"]),
        .init("schoolCorridor", .crowd, "a packed school corridor between lessons", ["school hallway ambience", "school corridor crowd"]),
        .init("feastHall", .crowd, "a great hall at a feast: many voices, cutlery", ["banquet hall crowd", "feast hall ambience"]),
        .init("trainStation", .crowd, "a railway station concourse", ["train station ambience", "railway station crowd"]),
        .init("cafeteria", .crowd, "a school or works cafeteria: trays, chatter", ["cafeteria ambience", "school cafeteria crowd"]),
        .init("classroomChatter", .crowd, "a classroom before the teacher arrives", ["classroom chatter students", "classroom noisy students"]),
        .init("schoolyard", .crowd, "a schoolyard or playground at break", ["playground children ambience", "schoolyard ambience"]),
        .init("gymnasium", .crowd, "a gym hall: balls, shoes squeaking, shouts", ["gymnasium ambience basketball", "sports hall ambience"]),
        .init("lockerRoom", .crowd, "a changing room: lockers, voices, showers", ["locker room ambience", "changing room ambience"]),
        .init("schoolBus", .crowd, "a school bus full of children", ["school bus interior kids", "bus full of children"]),
        .init("assemblyHall", .crowd, "a hall filling up before an assembly or lecture", ["auditorium crowd before", "lecture hall crowd ambience"]),
        .init("stadium", .crowd, "a stadium crowd during a match", ["stadium crowd ambience", "football crowd ambience"]),
        .init("theatreFoyer", .crowd, "a theatre before the curtain: the audience settling", ["theater audience before show", "theatre foyer crowd"]),
        .init("congregation", .crowd, "a congregation gathering, murmuring", ["church congregation murmur", "church crowd ambience"]),
        .init("courtroomGallery", .crowd, "a courtroom stirring, a gallery murmuring", ["courtroom crowd murmur", "courtroom gallery"]),
        .init("partyIndoors", .crowd, "a party in a house or flat: voices, glasses", ["house party ambience", "party chatter indoors"]),
        .init("gardenParty", .crowd, "a garden party or reception outdoors", ["garden party ambience", "outdoor party chatter"]),
        .init("restaurant", .crowd, "a busy restaurant: plates, chatter", ["restaurant ambience", "busy restaurant"]),
        .init("hotelLobby", .crowd, "a hotel lobby: luggage, a bell, voices", ["hotel lobby ambience", "hotel lobby crowd"]),
        .init("airportTerminal", .crowd, "an airport terminal: voices, wheels, echo", ["airport terminal ambience", "airport crowd"]),
        .init("shoppingMall", .crowd, "a shopping mall or department store", ["shopping mall ambience", "department store ambience"]),
        .init("supermarket", .crowd, "a supermarket: trolleys, tills, voices", ["supermarket ambience", "grocery store ambience"]),
        .init("busStation", .crowd, "a bus station or stop with a crowd", ["bus station ambience", "bus terminal crowd"]),
        .init("subwayStation", .crowd, "an underground platform with a crowd", ["subway station platform ambience", "metro station crowd"]),
        .init("hospitalWaitingRoom", .crowd, "a busy emergency waiting room", ["hospital waiting room", "emergency room waiting ambience"]),
        .init("openPlanOffice", .crowd, "an open-plan office: phones, chatter, printers", ["open plan office ambience", "busy office ambience"]),
        .init("newsroom", .crowd, "a newsroom or busy office in a hurry", ["newsroom ambience", "busy newsroom"]),
        .init("tradingFloor", .crowd, "a trading floor or exchange", ["trading floor ambience", "stock exchange floor"]),
        .init("prisonYard", .crowd, "a prison yard: voices, a ball, a whistle", ["prison yard ambience", "prison yard crowd"]),
        .init("armyCamp", .crowd, "an army camp: men, horses, hammering", ["army camp ambience", "military camp ambience"]),
        .init("bazaar", .crowd, "a bazaar or souk: close, loud, bells", ["bazaar ambience", "souk market ambience"]),
        .init("fairground", .crowd, "a fairground or carnival crowd", ["fairground ambience crowd", "carnival crowd ambience"]),
        .init("casino", .crowd, "a casino: machines, chips, voices", ["casino ambience", "casino slot machines ambience"]),
        .init("swimmingPool", .crowd, "an indoor pool: splashes, echoing voices", ["indoor swimming pool ambience", "swimming pool echo"]),
        .init("beach", .crowd, "a busy beach: children, waves, gulls", ["beach crowd ambience", "busy beach children waves"]),
        .init("boardwalk", .crowd, "a seaside promenade or boardwalk", ["boardwalk ambience", "promenade crowd seaside"]),
        .init("diningCar", .crowd, "a train's dining car", ["dining car train ambience", "train restaurant car"]),
        .init("ballroom", .crowd, "a ballroom before the dance: voices, glasses", ["ballroom crowd ambience", "gala reception crowd"]),
        .init("barracks", .crowd, "a barracks: boots, voices, kit", ["barracks ambience", "military barracks interior"]),
        .init("lectureHall", .crowd, "a lecture hall or auditorium filling up", ["lecture hall ambience", "auditorium crowd"]),
        .init("nightMarket", .crowd, "a night market: stalls, sizzling, voices", ["night market ambience", "street food market night"]),
        .init("festival", .crowd, "a festival or fete crowd outdoors", ["festival crowd ambience", "outdoor festival crowd"]),
        .init("townSquare", .crowd, "a town square on a busy day", ["town square ambience", "plaza crowd ambience"]),
        .init("pubCrowd", .crowd, "a packed pub on a loud night", ["busy pub ambience", "crowded pub"]),
        .init("auction", .crowd, "an auction room or sale", ["auction room ambience", "auction crowd"]),
        .init("sportsCrowd", .crowd, "a crowd at a race, a fight or a match outdoors", ["racetrack crowd ambience", "sports crowd outdoor"]),
        // Towns and places
        .init("cityNight", .city, "a city at night: distant traffic, quiet streets", ["city night ambience", "city night distant traffic"]),
        .init("busyStreet", .city, "a busy city street: traffic close, footsteps", ["busy street ambience", "city street traffic ambience"]),
        .init("highway", .city, "a highway or motorway, cars passing", ["highway ambience", "motorway traffic ambience"]),
        .init("suburbanStreet", .city, "a suburban street: a car, a dog, birds", ["suburban street ambience", "suburb ambience quiet"]),
        .init("rainyStreetNight", .city, "a rainy city street at night, tyres hissing", ["city rain night ambience", "rainy street night traffic"]),
        .init("rooftop", .city, "a rooftop: the city below, wind", ["rooftop city ambience", "city rooftop wind traffic"]),
        .init("alleyNight", .city, "a back alley at night, the city far off", ["alley night ambience", "city alley night"]),
        .init("docks", .city, "modern docks: cranes, water, engines", ["docks ambience cranes", "harbor industrial ambience"]),
        .init("industrialZone", .city, "an industrial district: hum, trucks, clatter", ["industrial ambience", "industrial area ambience"]),
        .init("smallTownStreet", .city, "a small town's main street, a car now and then", ["small town street ambience", "quiet town street"]),
        .init("cityPark", .city, "a city park: birds, a road beyond the trees", ["city park ambience traffic birds", "urban park ambience"]),
        .init("churchBells", .oldTown, "church bells ringing across a town", ["church bells distant", "church bells town"]),
        .init("villageMorning", .oldTown, "a village waking: a cart, hens, a far bell", ["village morning ambience", "old village ambience"]),
        .init("cobbledNight", .oldTown, "a cobbled street at night: a dog, a cart, a watchman", ["old town night ambience", "medieval street night"]),
        .init("castleCourtyard", .oldTown, "a castle courtyard: horses, armour, bustle", ["castle courtyard ambience", "medieval castle ambience"]),
        .init("harbourTown", .oldTown, "an old harbour town: gulls, carts, rigging", ["old harbour town ambience", "harbour town gulls carts"]),
        .init("marketDay", .oldTown, "market day in an old town square", ["medieval market ambience", "market day old town"]),
        .init("villageEvening", .oldTown, "a village at dusk: smoke, a dog, voices far off", ["village evening ambience", "village dusk ambience"]),
        // Travel
        .init("gallop", .horses, "riding at a gallop", ["horse galloping", "horse gallop ride"]),
        .init("trot", .horses, "riding at a trot", ["horse trotting", "horse trot ride"]),
        .init("horseAtAWalk", .horses, "a horse at a walk, reins and harness", ["horse walking hooves", "horse walk saddle creak"]),
        .init("stagecoach", .horses, "inside a stagecoach or carriage on the road", ["stagecoach interior", "horse carriage ride interior"]),
        .init("wagonTrain", .horses, "a wagon or ox cart on a rough track", ["wagon wheels dirt road", "ox cart wheels"]),
        .init("camelCaravan", .horses, "a camel caravan: bells, sand, wind", ["camel caravan", "camels walking desert bells"]),
        .init("dogSled", .horses, "a dog sled over snow: runners, panting dogs", ["dog sled snow", "sled dogs running snow"]),
        .init("marchingColumn", .horses, "an army on the march: boots, harness, wagons", ["marching army ambience", "soldiers marching boots"]),
        .init("steamTrain", .train, "a steam train on the move", ["steam train", "steam train journey interior"]),
        .init("subway", .train, "inside an underground train", ["subway train interior", "metro train interior"]),
        .init("sleeperNight", .train, "a sleeping car at night, the rails soft", ["train night interior quiet", "sleeper train ambience"]),
        .init("tram", .train, "inside a tram or streetcar", ["tram interior ambience", "streetcar interior"]),
        .init("freightTrain", .train, "riding in a freight car or on a slow goods train", ["freight train interior", "boxcar train ambience"]),
        .init("shipStorm", .ship, "a ship in a storm: groaning timbers, heavy seas", ["ship storm creaking waves", "sailing ship storm"]),
        .init("belowDecks", .ship, "below decks: creaks, water, muffled voices", ["ship below deck creaking", "ship hold interior"]),
        .init("calmSailing", .ship, "a sailing ship in a light wind, calm sea", ["sailing boat calm", "sailboat gentle sailing"]),
        .init("steamship", .ship, "a steamship: engine throb, water, gulls", ["steamship engine", "steam boat engine water"]),
        .init("factoryFloor", .machinery, "a factory floor: presses, belts, hum", ["factory floor ambience", "factory machines"]),
        .init("engineRoom", .machinery, "an engine room: pistons, steam, heat", ["engine room ambience", "ship engine room"]),
        .init("construction", .machinery, "a building site: machines, hammering, a crane", ["construction site ambience", "building site ambience"]),
        .init("sawmill", .machinery, "a sawmill: saws, belts, timber", ["sawmill ambience", "sawmill machinery"]),
        .init("mineWorkings", .machinery, "a working mine: carts, drills, pumps", ["mine machinery ambience", "underground mine working"]),
        .init("windmill", .machinery, "a windmill: sails creaking, gears, grain", ["windmill ambience", "windmill creaking gears"]),
        .init("powerPlant", .machinery, "a power plant or turbine hall", ["power plant ambience", "turbine hall hum"]),
        .init("clockwork", .machinery, "clockwork or gears turning close by", ["clockwork gears", "gears mechanism ticking"]),
        .init("generator", .machinery, "a generator running outside", ["generator running", "diesel generator ambience"]),
        .init("grandfatherClock", .clock, "a grandfather clock ticking in a hall", ["grandfather clock ticking", "long case clock tick"]),
        .init("mantelClock", .clock, "a small clock ticking in a quiet study", ["mantel clock ticking", "small clock ticking room"]),
        .init("clockShop", .clock, "a clockmaker's: many clocks ticking", ["many clocks ticking", "clock shop ambience"]),
        .init("car", .motorVehicle, "inside a moving car", ["car interior driving", "car driving interior ambience"]),
        .init("bus", .motorVehicle, "inside a bus or coach", ["bus interior ambience", "coach interior driving"]),
        .init("truck", .motorVehicle, "a truck's cab on the road", ["truck cab interior", "truck driving interior"]),
        .init("motorbike", .motorVehicle, "riding a motorbike: engine and wind", ["motorcycle riding", "motorbike engine wind"]),
        .init("oldCar", .motorVehicle, "an old car rattling along", ["vintage car driving", "old car engine interior"]),
        .init("electricCar", .motorVehicle, "an electric car, nearly silent, tyres on the road", ["electric car interior", "electric vehicle driving quiet"]),
        .init("taxiNight", .motorVehicle, "a taxi at night through the city", ["taxi interior night city", "car interior city night"]),
        .init("airliner", .aircraft, "inside an airliner in flight", ["airplane cabin ambience", "airliner cabin interior"]),
        .init("smallPlane", .aircraft, "a small propeller plane", ["small plane interior", "propeller plane cabin"]),
        .init("helicopter", .aircraft, "inside a helicopter", ["helicopter interior", "helicopter cabin ambience"]),
        .init("airship", .aircraft, "an airship's gondola: engines far off, wind", ["airship ambience", "zeppelin interior"]),
        .init("bridge", .spaceship, "a spaceship's bridge: instruments, soft beeps", ["spaceship bridge ambience", "starship bridge ambience"]),
        .init("cryoBay", .spaceship, "a cryo bay or medical bay: a hiss, a slow pulse", ["sci-fi medical bay ambience", "cryo chamber ambience"]),
        .init("spaceStation", .spaceship, "a space station corridor: ventilation, hum", ["space station ambience", "sci-fi corridor ambience"]),
        .init("shuttle", .spaceship, "a small shuttle or lander, rougher engines", ["sci-fi shuttle interior", "small spacecraft interior"]),
        .init("engineDeck", .spaceship, "a spaceship's engine deck, a deep throb", ["spaceship engine room", "starship engine hum"]),
        // Elsewhere
        .init("deepSpace", .deepDrone, "the void of space, a faint hull hum", ["deep space ambience", "outer space ambience"]),
        .init("dreamscape", .deepDrone, "a dream or vision, soft and unreal", ["dream ambience", "ethereal ambience soft"]),
        .init("eerieStillness", .deepDrone, "an eerie stillness, a low dread", ["eerie ambience", "horror ambience low"]),
        .init("magicalHush", .deepDrone, "a magical presence, a shimmering stillness", ["magical ambience", "mystical ambience"]),
        // What the characters are doing
        .init("walkingGravel", .footsteps, "walking on gravel or a stony path", ["footsteps gravel walking", "walking gravel path"]),
        .init("walkingWoodFloor", .footsteps, "walking on a wooden floor or boards", ["footsteps wooden floor", "walking wood floor creak"]),
        .init("walkingStoneCorridor", .footsteps, "walking a stone corridor or flagged floor, echoing", ["footsteps stone corridor echo", "footsteps stone floor"]),
        .init("walkingSnow", .footsteps, "walking through snow, crunching", ["footsteps snow crunch", "walking in snow"]),
        .init("walkingLeaves", .footsteps, "walking through leaves or undergrowth", ["footsteps leaves forest", "walking dry leaves"]),
        .init("walkingWetStreet", .footsteps, "walking a wet street, splashing a little", ["footsteps wet pavement", "walking wet street puddles"]),
        .init("walkingSand", .footsteps, "walking on sand", ["footsteps sand beach", "walking sand"]),
        .init("walkingStairs", .footsteps, "climbing or descending stairs", ["footsteps stairs", "walking up stairs wooden"]),
        .init("walkingGrass", .footsteps, "walking through grass or a meadow", ["footsteps grass", "walking tall grass"]),
        .init("walkingMud", .footsteps, "trudging through mud", ["footsteps mud squelch", "walking mud boots"]),
        .init("heelsOnTile", .footsteps, "hard heels on tile or marble", ["high heels tile floor", "footsteps marble heels"]),
        .init("sneaking", .footsteps, "creeping, slow careful steps", ["sneaking footsteps slow", "creeping footsteps quiet"]),
        .init("bootsOnDeck", .footsteps, "boots on a ship's deck", ["footsteps ship deck wood", "boots wooden deck"]),
        .init("limping", .footsteps, "an uneven walk, a limp, a stick", ["footsteps limp cane", "walking stick footsteps"]),
        .init("runningStreet", .running, "running down a street or pavement", ["running footsteps street", "running pavement footsteps"]),
        .init("runningForest", .running, "running through woods, branches and leaves", ["running footsteps forest", "running through woods"]),
        .init("runningCorridor", .running, "running down a corridor, echoing", ["running footsteps corridor", "running hallway echo"]),
        .init("runningGravel", .running, "running on gravel or a stony path", ["running footsteps gravel", "running gravel path"]),
        .init("runningStairs", .running, "running up or down stairs", ["running stairs footsteps", "running down stairs"]),
        .init("runningGrass", .running, "running across grass or a field", ["running footsteps grass", "running field grass"]),
        .init("runningSnow", .running, "running through snow", ["running footsteps snow", "running in snow crunch"]),
        .init("runningShallows", .running, "running or splashing through shallow water", ["running water splashing footsteps", "running through shallow water"]),
        .init("chase", .running, "a chase: several sets of running feet", ["chase footsteps running group", "people running chase"]),
        .init("heavyBreathing", .breathing, "heavy breathing after effort", ["heavy breathing exhausted", "breathing hard"]),
        .init("panickedBreathing", .breathing, "fast, frightened breathing", ["panicked breathing", "scared breathing fast"]),
        .init("sleepingBreathing", .breathing, "the slow breath of someone asleep", ["sleeping breathing slow", "breathing asleep"]),
        .init("breathingInMask", .breathing, "breath inside a mask, helmet or respirator", ["breathing mask respirator", "breathing helmet"]),
        .init("labouredBreathing", .breathing, "laboured, sick or wounded breathing", ["laboured breathing", "wheezing breathing"]),
        .init("breathingUnderwater", .breathing, "a diver's breath and bubbles", ["scuba breathing bubbles", "underwater breathing regulator"]),
        .init("racingHeartbeat", .heartbeat, "a heart racing", ["heartbeat fast", "racing heartbeat"]),
        .init("slowHeartbeat", .heartbeat, "a slow, heavy heartbeat", ["heartbeat slow", "slow heartbeat loop"]),
        .init("swimmingStrokes", .swimming, "swimming, stroke after stroke", ["swimming strokes", "swimming freestyle water"]),
        .init("treadingWater", .swimming, "treading water, keeping afloat", ["treading water", "splashing water staying afloat"]),
        .init("wading", .swimming, "wading through water", ["wading water walking", "walking through water"]),
        .init("floating", .swimming, "floating still, water lapping at the ears", ["floating water lapping", "water lapping close"]),
        .init("rockFace", .climbing, "climbing a rock face: hands on stone, a scrape", ["rock climbing", "climbing rock scrape"]),
        .init("ropeClimb", .climbing, "climbing a rope", ["rope climbing creak", "climbing rope"]),
        .init("ladderRungs", .climbing, "climbing a ladder", ["climbing ladder rungs", "ladder climbing wood"]),
        .init("treeClimb", .climbing, "climbing a tree: bark, leaves, branches", ["climbing tree branches", "tree climbing leaves"]),
        .init("scree", .climbing, "scrambling over loose scree", ["scree scramble rocks", "loose rocks scramble"]),
        .init("iceClimb", .climbing, "climbing ice: picks and crampons", ["ice climbing axe", "ice axe crampons"]),
        .init("swordFight", .fighting, "a sword fight: blades, feet, breath", ["sword fight", "sword fighting clash"]),
        .init("fistFight", .fighting, "a fist fight or a scuffle", ["fist fight punches", "fight scuffle punches"]),
        .init("battle", .fighting, "a battle around them: steel, shouts, hooves", ["medieval battle ambience", "battle ambience swords"]),
        .init("siege", .fighting, "a siege: engines, stone, shouts from the walls", ["siege battle ambience", "castle siege ambience"]),
        .init("brawl", .fighting, "a tavern brawl: furniture, fists", ["bar fight brawl", "tavern brawl"]),
        .init("armouredMelee", .fighting, "armoured men at close quarters", ["armor fight clank", "knights fighting armour"]),
        .init("quillOnPaper", .writing, "a quill scratching on paper", ["quill writing paper", "quill pen scratching"]),
        .init("penOnPaper", .writing, "a pen on paper", ["pen writing paper", "writing with pen"]),
        .init("pencilOnPaper", .writing, "a pencil on paper", ["pencil writing paper", "pencil sketching"]),
        .init("typing", .writing, "typing on a keyboard", ["keyboard typing", "typing computer keyboard"]),
        .init("pageTurning", .writing, "reading: pages turning now and then", ["page turning book", "book pages turning"]),
        .init("chalkOnBoard", .writing, "chalk on a blackboard", ["chalk blackboard writing", "chalk on chalkboard"]),
        .init("cutleryAndPlates", .meal, "a meal: cutlery on plates, a glass set down", ["cutlery plates dinner", "dinner plates cutlery"]),
        .init("teaThings", .meal, "tea: cups on saucers, a spoon, a pot", ["tea cups saucers", "tea pouring cup spoon"]),
        .init("tavernMeal", .meal, "a meal at an inn: wooden bowls, tankards", ["tankards wooden table", "medieval tavern dishes"]),
        .init("campMeal", .meal, "a meal by a fire: tin plates, a pot", ["camp cooking tin plates", "tin plates spoons"]),
        .init("washingUp", .meal, "dishes being washed", ["washing dishes sink", "dishes washing up"]),
        .init("digging", .work, "digging: a spade in earth", ["digging shovel dirt", "shovel digging soil"]),
        .init("choppingWood", .work, "chopping wood with an axe", ["chopping wood axe", "wood chopping"]),
        .init("sweeping", .work, "sweeping a floor or a yard", ["sweeping broom floor", "broom sweeping"]),
        .init("scrubbing", .work, "scrubbing a floor", ["scrubbing floor brush", "scrubbing brush bucket"]),
        .init("hammering", .work, "hammering: nails, a workbench", ["hammering nails", "hammer nails wood"]),
        .init("sawing", .work, "sawing wood by hand", ["hand saw wood", "sawing wood"]),
        .init("harvesting", .work, "harvesting: a scythe, a sickle, sheaves", ["scythe cutting grass", "harvest sickle wheat"]),
        .init("rowing", .work, "rowing: oars dipping and creaking", ["rowing oars dipping", "oars rowlocks rowing"]),
        .init("washingClothes", .work, "washing clothes by hand, at a tub or a river", ["washing clothes hand water", "laundry washing tub"]),
        .init("shovellingSnow", .work, "shovelling snow", ["shoveling snow", "snow shovel scrape"]),
        .init("ploughing", .work, "ploughing: a horse, harness, the share in the soil", ["horse plough field", "ploughing horse"]),
        .init("knitting", .work, "knitting or sewing by hand, needles clicking", ["knitting needles", "knitting needles clicking"]),
    ]

    /// The starter variants, as the scorer and the catalogue file use them.
    public static var starterVariants: [SoundVariant] { variants.map(\.variant) }

    public static func variants(of sound: AmbientSound) -> [Variant] {
        variants.filter { $0.of == sound }
    }

    public static func variant(_ id: String) -> Variant? {
        variants.first { $0.id == id }
    }

    // MARK: - What places sound like

    /// Typical soundscapes for common places and how they change with the place's
    /// state. The scorer reads this; the text always decides.
    public static let placeGuide: [PlaceGuide] = [
        .init("school corridor", [
            .init("after hours, empty", "emptyHall.schoolHallwayEmpty soft"),
            .init("lessons on, a few people passing", "emptyHall.schoolHallwayEmpty soft, murmur.hallwayWhispers faint"),
            .init("between lessons, the bell", "crowd.schoolCorridor full"),
            .init("everyone whispering or staring at the character", "murmur.hallwayWhispers soft, emptyHall.schoolHallwayEmpty faint"),
            .init("a fight, uproar, everyone talking about the character", "crowd.schoolCorridor loud"),
        ]),
        .init("classroom", [
            .init("empty", "roomTone.classroomEmpty faint"),
            .init("the teacher talking, pupils quiet", "hushedRoom.classroomQuiet soft"),
            .init("a test or silent work", "hushedRoom.examHall soft, clock faint"),
            .init("teacher out, pupils whispering", "murmur.classroomWhispers soft"),
            .init("before the teacher arrives, chaos", "crowd.classroomChatter full"),
        ]),
        .init("school cafeteria or dining hall", [
            .init("lunchtime", "crowd.cafeteria full"),
            .init("emptying out", "murmur.quietConversation soft, emptyHall faint"),
        ]),
        .init("schoolyard or playground", [
            .init("break time", "crowd.schoolyard full"),
            .init("lessons on, empty", "birdsong.park faint, city.suburbanStreet faint"),
        ]),
        .init("library", [
            .init("open, people reading", "hushedRoom.library soft"),
            .init("a whispered conversation", "hushedRoom.library soft, murmur.whispers faint"),
            .init("closed, empty", "roomTone faint, clock faint"),
        ]),
        .init("ordinary house or flat", [
            .init("daytime, quiet", "roomTone faint"),
            .init("evening with a fire", "fireplace soft, clock faint"),
            .init("night, everyone asleep", "roomTone.houseAtNight faint"),
            .init("rain outside", "rainIndoors soft, roomTone faint"),
            .init("a window open on a summer day", "birdsong.garden soft, roomTone faint"),
            .init("a family meal", "murmur.dinnerTable soft, kitchen.homeKitchen faint"),
            .init("a party", "crowd.partyIndoors full"),
        ]),
        .init("kitchen", [
            .init("cooking", "kitchen.homeKitchen soft"),
            .init("washing up", "kitchen.dishwashing soft"),
            .init("at night", "electricHum.fridgeAtNight faint"),
        ]),
        .init("bedroom", [
            .init("night", "roomTone.houseAtNight faint"),
            .init("morning, birds outside", "roomTone.bedroomMorning faint, birdsong faint"),
            .init("rain at night", "rainIndoors.rainOnWindowNight soft"),
        ]),
        .init("office", [
            .init("working day, quiet", "electricHum.office faint, hushedRoom.officeQuiet soft"),
            .init("busy open-plan", "crowd.openPlanOffice full"),
            .init("after hours", "roomTone.officeAfterHours faint"),
        ]),
        .init("hospital", [
            .init("a ward by day", "electricHum.hospitalWard soft, murmur.hospitalRoom faint"),
            .init("a ward at night", "electricHum.hospitalNight soft"),
            .init("a corridor", "emptyHall.hospitalCorridor soft"),
            .init("the waiting room", "crowd.hospitalWaitingRoom full"),
        ]),
        .init("cafe or restaurant", [
            .init("busy", "crowd.cafe full"),
            .init("nearly empty", "murmur.quietConversation soft, kitchen faint"),
            .init("the kitchen", "kitchen.restaurantKitchen full"),
        ]),
        .init("pub, bar or tavern", [
            .init("busy night", "crowd.tavern full, fireplace faint"),
            .init("quiet afternoon", "murmur.quietBar soft, fireplace faint"),
            .init("a brawl, uproar", "crowd.pubCrowd loud"),
        ]),
        .init("church or cathedral", [
            .init("empty", "emptyHall.cathedral soft"),
            .init("before the service, people gathering", "crowd.congregation soft, emptyHall.cathedral faint"),
            .init("during the service, hushed", "hushedRoom.chapel soft"),
            .init("bells ringing outside", "oldTown.churchBells soft"),
        ]),
        .init("courtroom", [
            .init("in session", "hushedRoom.courtroom soft"),
            .init("the gallery stirring, uproar", "crowd.courtroomGallery full"),
        ]),
        .init("shop", [
            .init("small, quiet", "murmur.smallShop faint"),
            .init("supermarket or mall", "crowd.supermarket full"),
        ]),
        .init("city street", [
            .init("daytime", "city.busyStreet full"),
            .init("night", "city.cityNight soft"),
            .init("rain at night", "city.rainyStreetNight soft, rain soft"),
            .init("a quiet suburb", "city.suburbanStreet soft, birdsong faint"),
            .init("a park", "city.cityPark soft"),
        ]),
        .init("old town or village (before cars)", [
            .init("day, streets busy", "oldTown full"),
            .init("market day", "crowd.marketplace full, oldTown faint"),
            .init("night", "oldTown.cobbledNight soft"),
            .init("dawn", "oldTown.villageMorning soft, birdsong faint"),
        ]),
        .init("castle", [
            .init("the great hall, a feast", "crowd.feastHall full, fireplace soft"),
            .init("the great hall, empty", "emptyHall.stoneHall soft, fireplace faint"),
            .init("a corridor at night", "emptyHall.castleCorridor soft, campfire.torches faint"),
            .init("the courtyard", "oldTown.castleCourtyard soft"),
            .init("the battlements", "wind.battlements soft"),
            .init("the dungeon", "dripping.dungeon soft"),
        ]),
        .init("forest", [
            .init("day", "forest soft, birdsong faint"),
            .init("night", "nightForest soft"),
            .init("rain", "rain.rainOnLeaves soft"),
            .init("winter", "snow.snowyForest soft"),
            .init("a stream nearby", "forest soft, river faint"),
        ]),
        .init("open country", [
            .init("summer day", "birdsong.summerMeadow soft, wind faint"),
            .init("windy hills or moor", "wind soft"),
            .init("night", "nightInsects soft"),
            .init("a farm", "farmyard soft"),
        ]),
        .init("sea and coast", [
            .init("a beach", "seaShore soft"),
            .init("a harbour", "seaShore.harbour soft"),
            .init("cliffs", "seaShore.cliffs soft"),
            .init("a storm on the coast", "seaShore.stormySea full, strongWind soft"),
            .init("at sea on a sailing ship", "ship soft, openSea soft"),
            .init("at sea in a storm", "ship.shipStorm full, strongWind soft, thunder faint"),
            .init("below decks", "ship.belowDecks soft"),
        ]),
        .init("camp", [
            .init("evening, a fire", "campfire soft, nightInsects faint"),
            .init("a tent in the rain", "rainIndoors.tentRain soft"),
            .init("a tent in the wind", "wind.tentWind soft"),
            .init("an army camp", "crowd.armyCamp soft, campfire faint"),
        ]),
        .init("car journey", [
            .init("driving", "motorVehicle.car soft"),
            .init("driving in rain", "motorVehicle.car soft, rainIndoors.rainOnCarRoof faint"),
            .init("parked, rain on the roof", "rainIndoors.rainOnCarRoof soft"),
            .init("a bus", "motorVehicle.bus soft"),
        ]),
        .init("train journey", [
            .init("daytime", "train soft"),
            .init("night, a sleeper", "train.sleeperNight faint"),
            .init("the station", "crowd.trainStation full"),
            .init("the underground", "train.subway soft"),
        ]),
        .init("plane journey", [
            .init("in flight", "aircraft.airliner soft"),
            .init("the terminal", "crowd.airportTerminal full"),
        ]),
        .init("horse and carriage", [
            .init("riding", "horses soft"),
            .init("inside a coach", "horses.stagecoach soft"),
            .init("a stable", "farmyard.stable soft"),
        ]),
        .init("spaceship", [
            .init("the bridge", "spaceship.bridge soft"),
            .init("a corridor or quarters", "spaceship soft"),
            .init("the engine deck", "spaceship.engineDeck full"),
            .init("outside, in space", "deepDrone.deepSpace soft"),
        ]),
        .init("underground", [
            .init("a cave", "dripping.cave soft"),
            .init("a dungeon or cell", "dripping.dungeon soft"),
            .init("a mine at work", "machinery.mineWorkings soft, dripping faint"),
            .init("a sewer or tunnel", "dripping.sewer soft"),
        ]),
        .init("workplaces", [
            .init("a smithy", "workshop.blacksmith full"),
            .init("a carpenter", "workshop.carpentry soft"),
            .init("a factory", "machinery.factoryFloor full"),
            .init("a laboratory", "electricHum.laboratory faint"),
            .init("a farm", "farmyard soft"),
        ]),
        .init("prison", [
            .init("a cell", "emptyHall.prisonBlock faint"),
            .init("the block, doors and echoes", "emptyHall.prisonBlock soft"),
            .init("the yard", "crowd.prisonYard full"),
        ]),
        .init("dreams, visions, the uncanny", [
            .init("a dream", "deepDrone.dreamscape faint"),
            .init("something wrong, a dread", "deepDrone.eerieStillness faint"),
            .init("magic at work", "deepDrone.magicalHush faint"),
        ]),
    ]

    // MARK: - Export

    /// The catalogue as JSON for the fetch script: the sound families with their search
    /// words and folders, every starter variant, the one-off sounds, and the place guide.
    public static func export() throws -> Data {
        var sounds: [[String: Any]] = []
        for sound in AmbientSound.allCases {
            sounds.append([
                "id": sound.rawValue,
                "folder": sound.folderName,
                "group": sound.group.rawValue,
                "about": sound.guidance,
                "queries": sound.searchQueries,
                "voices": sound.isVoices,
                "weather": sound.scope == .weather,
                "scope": sound.scope.rawValue,
                "replacesMusic": sound.musicPolicy == .replacesMusic,
                "levelOffsetDB": sound.levelOffsetDB,
            ])
        }
        let variants: [[String: Any]] = Self.variants.map { variant in
            [
                "id": variant.id,
                "of": variant.of.rawValue,
                "folder": variant.folderName,
                "about": variant.about,
                "search": variant.searches.first ?? variant.about,
                "queries": variant.searches,
            ]
        }
        let oneShots: [[String: Any]] = OneShotSound.allCases.map { sound in
            [
                "id": sound.rawValue,
                "folder": sound.folderName,
                "about": sound.guidance,
                "queries": sound.search.queries,
                "longestSeconds": sound.search.longestSeconds,
            ]
        }
        let places: [[String: Any]] = placeGuide.map { guide in
            ["place": guide.place, "states": guide.states.map { ["when": $0.when, "sounds": $0.sounds] }]
        }
        let transitions: [[String: Any]] = SceneTransition.allCases.map { transition in
            ["id": transition.rawValue, "about": transition.guidance, "seconds": transition.timeline.seconds]
        }
        let object: [String: Any] = [
            "version": version,
            "promptVersion": ClaudeScenePrompt.version,
            "sounds": sounds,
            "variants": variants,
            "oneShots": oneShots,
            "places": places,
            "transitions": transitions,
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}
