import Foundation

#if canImport(FoundationXML)
  import FoundationXML  // On Linux, XMLParser lives here.
#endif

/// Reads a podcast RSS 2.0 feed, with the iTunes tags and `content:encoded`.
public enum FeedParser {
  public static func parse(_ data: Data) throws -> PodcastFeed {
    let reader = FeedReader()
    let parser = XMLParser(data: data)
    parser.delegate = reader
    let finished = parser.parse()
    guard finished, parser.parserError == nil, reader.sawChannel else { throw FeedError.notAFeed }
    return reader.feed()
  }
}

/// The XML delegate. It remembers the path of open elements, so each piece of text is
/// filed by where it sits ("rss/channel/item/title"). Element names are read as written
/// (with their prefix, like "itunes:author"), because feeds use the usual prefixes.
private final class FeedReader: NSObject, XMLParserDelegate {
  private struct Item {
    var guid = "", title = "", pubDate = "", duration = "", season = "", number = ""
    var description = "", summary = "", content = "", image = ""
    var audio: (url: URL, type: String, bytes: Int64?)?
  }

  private var path: [String] = []
  private var text = ""
  private var item: Item?
  private let dates = FeedParser.DateParser()
  private var episodes: [FeedEpisode] = []

  private(set) var sawChannel = false
  private var title = "", author = "", showDescription = "", summary = "", subtitle = ""
  private var link = "", language = "", itunesImage = "", plainImage = ""
  private var topCategories: [String] = [], subCategories: [String] = []
  private var currentTop = ""

  func feed() -> PodcastFeed {
    PodcastFeed(
      title: title.isEmpty ? "Untitled podcast" : title,
      author: author.isEmpty ? nil : author,
      description: FeedParser.plainText([showDescription, summary, subtitle].first { !$0.isEmpty } ?? ""),
      imageURL: URL(string: itunesImage.isEmpty ? plainImage : itunesImage),
      link: URL(string: link),
      language: language.isEmpty ? nil : language,
      categories: topCategories + subCategories,
      episodes: episodes)
  }

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes: [String: String]
  ) {
    let name = elementName.lowercased()
    if path.isEmpty && name != "rss" {
      parser.abortParsing()  // An HTML page, an Atom feed or something else.
      return
    }
    path.append(name)
    text = ""
    switch path.joined(separator: "/") {
    case "rss/channel":
      sawChannel = true
    case "rss/channel/item":
      item = Item()
    case "rss/channel/itunes:image":
      if itunesImage.isEmpty { itunesImage = clean(attributes["href"] ?? "") }
    case "rss/channel/itunes:category":
      currentTop = clean(attributes["text"] ?? "")
      if !currentTop.isEmpty && !topCategories.contains(currentTop) { topCategories.append(currentTop) }
    case "rss/channel/itunes:category/itunes:category":
      let sub = clean(attributes["text"] ?? "")
      let name = "\(currentTop) › \(sub)"
      if !currentTop.isEmpty && !sub.isEmpty && !subCategories.contains(name) {
        subCategories.append(name)
      }
    case "rss/channel/item/itunes:image":
      item?.image = clean(attributes["href"] ?? "")
    case "rss/channel/item/enclosure":
      readEnclosure(attributes)
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    text += string
  }

  func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
    text += String(decoding: CDATABlock, as: UTF8.self)
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    guard !path.isEmpty else { return }
    let value = clean(text)
    switch path.joined(separator: "/") {
    case "rss/channel/title": if title.isEmpty { title = value }
    case "rss/channel/link": if link.isEmpty { link = value }
    case "rss/channel/language": if language.isEmpty { language = value }
    case "rss/channel/description": if showDescription.isEmpty { showDescription = value }
    case "rss/channel/itunes:summary": if summary.isEmpty { summary = value }
    case "rss/channel/itunes:subtitle": if subtitle.isEmpty { subtitle = value }
    case "rss/channel/itunes:author": if author.isEmpty { author = value }
    case "rss/channel/image/url": if plainImage.isEmpty { plainImage = value }
    case "rss/channel/item/title": item?.title = value
    case "rss/channel/item/guid": item?.guid = value
    case "rss/channel/item/pubdate": item?.pubDate = value
    case "rss/channel/item/itunes:duration": item?.duration = value
    case "rss/channel/item/itunes:season": item?.season = value
    case "rss/channel/item/itunes:episode": item?.number = value
    case "rss/channel/item/description": item?.description = value
    case "rss/channel/item/itunes:summary": item?.summary = value
    case "rss/channel/item/content:encoded": item?.content = value
    case "rss/channel/item": finishItem()
    default: break
    }
    path.removeLast()
    text = ""
  }

  private func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Keeps the first enclosure that looks like audio.
  private func readEnclosure(_ attributes: [String: String]) {
    guard item?.audio == nil, let url = URL(string: clean(attributes["url"] ?? "")),
      url.scheme?.lowercased().hasPrefix("http") == true
    else { return }
    let type = clean(attributes["type"] ?? "").lowercased()
    guard FeedParser.looksLikeAudio(type: type, url: url) else { return }
    let bytes = Int64(clean(attributes["length"] ?? "")).flatMap { $0 > 0 ? $0 : nil }
    item?.audio = (url, type.isEmpty ? FeedParser.guessedType(url) : type, bytes)
  }

  private func finishItem() {
    defer { item = nil }
    guard let item, let audio = item.audio else { return }
    let notes = [item.content, item.description, item.summary]
      .map(FeedParser.plainText).first { !$0.isEmpty } ?? ""
    episodes.append(
      FeedEpisode(
        guid: item.guid.isEmpty ? audio.url.absoluteString : item.guid,
        title: item.title.isEmpty ? "Untitled episode" : FeedParser.plainText(item.title),
        published: dates.parse(item.pubDate),
        durationSeconds: FeedParser.parseDuration(item.duration),
        notes: notes,
        audioURL: audio.url,
        audioType: audio.type,
        audioBytes: audio.bytes,
        imageURL: URL(string: item.image).flatMap { item.image.isEmpty ? nil : $0 },
        season: Int(item.season),
        number: Int(item.number)))
  }
}
