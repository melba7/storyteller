import Foundation

/// The files of the Mac's teaching run, as its own Python functions wrote them for a tiny made-up
/// folder (`teach_library.document`, `teach_habits.summarize` and `teach_train.build_model`). The
/// text is pasted as it came out, so the phone's readers are tested against what the Mac writes.
enum MacFixtures {
  static let library = #"""
    {
     "version": 1,
     "writtenAt": 1700000000000,
     "ads": [
      {
       "feed": "https://show-a.test/feed",
       "scope": "all",
       "sort": "sponsor",
       "who": "Acme",
       "text": "Brought to you by Acme Socks, the softest socks you can buy online today and every day after that with free shipping on all orders over twenty dollars.",
       "length": 31.0,
       "seen": 3
      },
      {
       "feed": "https://www.Show-B.test/rss/",
       "scope": "show",
       "sort": "host_ask",
       "who": "",
       "text": "Join the Moon Club at moonclub dot example for bonus episodes and a weekly newsletter from your hosts and friends who love this show a great deal more than before",
       "length": 22.5,
       "seen": 1
      }
     ]
    }
    """#

  static let habits = #"""
    {
     "version": 1,
     "writtenAt": 1700000000000,
     "shows": [
      {
       "feed": "https://show-a.test/feed",
       "title": "Show A",
       "episodes": 3,
       "opensWithAd": 3,
       "openingStarts": 5.0,
       "openingEnds": 40.0,
       "breaks": 1,
       "adSeconds": 35.0
      },
      {
       "feed": "https://www.Show-B.test/rss/",
       "title": "Show B",
       "episodes": 1,
       "opensWithAd": 0,
       "openingStarts": null,
       "openingEnds": null,
       "breaks": 1,
       "adSeconds": 60.0
      }
     ]
    }
    """#

  static let model = #"""
    {"version":1,"buckets":262144,"classes":["none","sponsor","network_promo","host_ask","intro_credits"],"thresholds":{"start":0.6,"stay":0.4,"sure":0.85},"weights":{"7":[0.0,2.5,0.0,0.0,0.0],"9":[0.0,0.0,-1.25,0.0,0.0]},"trained":{"writtenAt":1700000000000,"episodes":12,"lines":400,"shelf":2,"heldOut":{"episodes":2,"lines":40,"anyAd":{"precision":0.8889,"recall":0.8},"classes":{}}}}
    """#

  static var libraryData: Data { Data(library.utf8) }
  static var habitsData: Data { Data(habits.utf8) }
  static var modelData: Data { Data(model.utf8) }

  /// The feed keys of the two shows, as the app's table has them.
  static let showA = "show-a.test/feed"
  static let showB = "show-b.test/rss"
}
