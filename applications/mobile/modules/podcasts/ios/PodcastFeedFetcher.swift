// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
import Foundation

/// Why a feed could not be downloaded. The message is shown to the listener as it is.
struct PodcastFetchError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
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

    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    request.setValue("StorytellerLofi/1.0 podcast client", forHTTPHeaderField: "User-Agent")
    request.setValue(
      "application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8",
      forHTTPHeaderField: "Accept")

    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw PodcastFetchError(
        message: "The podcast's server answered with status \(http.statusCode).")
    }
    if response.expectedContentLength > Int64(maxBytes) {
      throw PodcastFetchError(message: "This feed is too big to read.")
    }

    var data = Data()
    for try await byte in bytes {
      data.append(byte)
      if data.count > maxBytes {
        throw PodcastFetchError(message: "This feed is too big to read.")
      }
    }
    return data
  }
}
