// LOFI-FORK: sponsor names taken from the links in an episode's notes (see FORK.md).
//
// Show notes list the offers of the episode: "betterhelp.com/show", "code POD at acme.com". The
// site's name is the name the hosts say when they read the ad. Foundation only.
import Foundation

enum SponsorNames {
  /// The shortest site name that counts. A shorter one would be found inside too many words.
  static let shortest = 4

  private static let sites = "com|net|org|io|co|fm|tv|me|ly|app|dev|shop|store"
  private static let host = #"((?:[a-z0-9-]+\.)+(?:\#(sites)))\b"#
  /// A web address with a path ("quince.com/pod"), and a web address next to a promo code
  /// ("code POD at acme.com"). A bare address says nothing: notes link sources all the time.
  private static let links = AdSignals.regexes([
    host + #"/[a-z0-9]"#, #"\bcode\s+[a-z0-9]+\s+at\s+"# + host,
  ])

  /// Sites that are never a sponsor: social networks, podcast apps and the companies that host
  /// or sell the show's ads (their "your ad choices" and privacy links end every note), link
  /// shortcuts, stores that notes link for books, and the hosts' own plugs.
  private static let notSponsors: Set<String> = [
    "instagram", "facebook", "twitter", "tiktok", "youtube", "youtu", "linkedin", "threads", "bsky",
    "reddit", "discord", "twitch", "snapchat", "pinterest", "mastodon", "whatsapp", "telegram",
    "spotify", "apple", "google", "amazon", "overcast", "pocketcasts", "castbox", "stitcher",
    "iheart", "iheartradio", "podbean", "podchaser", "deezer", "tunein", "soundcloud",
    "megaphone", "omnystudio", "omny", "acast", "podtrac", "adswizz", "art19", "podcastchoices",
    "simplecast", "buzzsprout", "libsyn", "audioboom", "spreaker", "captivate", "transistor",
    "wikipedia", "github", "gitlab", "medium", "linktree", "linktr",
    "patreon", "substack", "ko-fi", "kofi", "buymeacoffee", "bandcamp", "merch", "newsletter",
  ]

  /// The names the links in the notes give, in order of appearance and without doubles. A link
  /// to the show's own site (`showLink`) gives none.
  static func fromLinks(in notes: String, showLink: URL?) -> [String] {
    let own = showLink?.host.flatMap(name(ofHost:))
    var names: [String] = []
    let whole = NSRange(notes.startIndex..., in: notes)
    for link in links {
      for match in link.matches(in: notes, options: [], range: whole) {
        guard let range = Range(match.range(at: 1), in: notes),
          let found = name(ofHost: String(notes[range])), found.count >= shortest,
          found.contains(where: \.isLetter), found != own, !notSponsors.contains(found),
          !names.contains(found)
        else { continue }
        names.append(found)
      }
    }
    return names
  }

  /// The site's own name: the label before its ending, without "www" or a subdomain
  /// ("get.quince.com" gives "quince", "www.bbc.co.uk" gives "bbc").
  static func name(ofHost host: String) -> String? {
    var labels = host.lowercased().split(separator: ".").map(String.init)
    let second = ["co", "com", "org", "net", "ac", "gov"]
    if labels.count >= 3, labels.last?.count == 2, second.contains(labels[labels.count - 2]) {
      labels.removeLast()  // a country ending such as ".co.uk"
    }
    return labels.count >= 2 ? labels[labels.count - 2] : nil
  }
}
