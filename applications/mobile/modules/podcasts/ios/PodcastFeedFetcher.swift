// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
import Foundation

/// Why a feed could not be downloaded. The message is shown to the listener as it is.
struct PodcastFetchError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

extension URL {
  /// A plain http address as its https twin, because iOS blocks public http for everything but
  /// the player's own media loading. Any other address is returned as it is.
  var upgradedToHTTPS: URL {
    guard scheme?.lowercased() == "http", var parts = URLComponents(url: self, resolvingAgainstBaseURL: false)
    else { return self }
    parts.scheme = "https"
    return parts.url ?? self
  }
}

enum PodcastFeedFetcher {
  /// The most a feed may weigh. Real feeds are well under this.
  static let maxBytes = 30 * 1024 * 1024

  static func download(_ address: String) async throws -> Data {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https", url.host != nil
    else {
      throw PodcastFetchError(message: "That isn't a web link.")
    }

    // A plain http link is tried over https first. The app now allows plain http, so the
    // original address is the second try, for a feed that has no https at all.
    if scheme == "http", var secure = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      secure.scheme = "https"
      if let secureURL = secure.url, let data = try? await load(secureURL) {
        return data
      }
    }
    return try await load(url)
  }

  private static func load(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    request.setValue("StorytellerLofi/1.0 podcast client", forHTTPHeaderField: "User-Agent")
    request.setValue(
      "application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8",
      forHTTPHeaderField: "Accept")

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
      // Only if the build's App Transport Security setting ever stops allowing plain http.
      throw PodcastFetchError(message: "This feed only works over plain http, which iOS blocks.")
    }
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw PodcastFetchError(
        message: "The podcast's server answered with status \(http.statusCode).")
    }
    if response.expectedContentLength > Int64(maxBytes) || data.count > maxBytes {
      throw PodcastFetchError(message: "This feed is too big to read.")
    }
    return data
  }
}
