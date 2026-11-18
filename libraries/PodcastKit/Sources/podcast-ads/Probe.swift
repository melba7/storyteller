// LOFI-FORK: `podcast-ads --probe <address>`: downloads the start of an episode twice as two
// different listeners and says where the copies differ (see FORK.md). No keys, no audio saved.
import Foundation
import PodcastAudioMatch

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The first bytes of one address, read until `limit` bytes are in and then stopped, so a
/// server that ignores the Range header does not send the whole episode.
final class HeadDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  var data = Data()
  var status = 0
  var finalURL: URL?
  var headers: [String: String] = [:]
  var chain: [String] = []
  var failure: String?
  private let limit: Int
  private let done = DispatchSemaphore(value: 0)
  private var finished = false

  init(limit: Int) { self.limit = limit }

  static func fetch(_ address: URL, userAgent: String, limit: Int, timeout: Double = 30) -> HeadDownload {
    let job = HeadDownload(limit: limit)
    var request = URLRequest(url: address, timeoutInterval: timeout)
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("bytes=0-\(limit - 1)", forHTTPHeaderField: "Range")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    let session = URLSession(configuration: .ephemeral, delegate: job, delegateQueue: nil)
    let task = session.dataTask(with: request)
    task.resume()
    if job.done.wait(timeout: .now() + timeout * 2) == .timedOut {
      task.cancel()
      job.failure = "timed out"
    }
    session.invalidateAndCancel()
    return job
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
  ) {
    chain.append(response.url?.host ?? "?")
    completionHandler(request)  // the same headers go along, so the User-Agent stays
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    if let http = response as? HTTPURLResponse {
      status = http.statusCode
      finalURL = http.url
      for (key, value) in http.allHeaderFields { headers["\(key)".lowercased()] = "\(value)" }
    }
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
    data.append(chunk)
    if data.count >= limit {
      data = data.prefix(limit)
      finish()
      dataTask.cancel()
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error, !finished { failure = error.localizedDescription }
    finish()
  }

  private func finish() {
    guard !finished else { return }
    finished = true
    done.signal()
  }
}

enum Probe {
  static let firstAgent = "StorytellerLofi/1.0 podcast client"
  static let secondAgent = "StorytellerLofi-probe/1.0 (second listener)"
  static let limit = 3_000_000

  static func seconds(_ value: Double) -> String {
    let total = Int(value)
    return String(format: "%d:%02d.%d", total / 60, total % 60, Int((value - Double(total)) * 10))
  }

  /// Prints the report and answers the exit code.
  static func run(_ text: String) -> Int32 {
    guard let address = URL(string: text), let scheme = address.scheme, scheme.hasPrefix("http") else {
      say("That is not a web address: \(text)")
      return 1
    }
    print("Episode address: \(text)")
    print("Downloading the first \(limit / 1_000_000) MB twice, with two different User-Agents.")
    print("")
    var copies: [(job: HeadDownload, parse: MP3Parse)] = []
    for (name, agent) in [("Copy A", firstAgent), ("Copy B", secondAgent)] {
      let job = HeadDownload.fetch(address, userAgent: agent, limit: limit)
      if let failure = job.failure, job.data.isEmpty {
        say("\(name) did not download: \(failure)")
        return 1
      }
      let parse = MP3Frames.parse([UInt8](job.data))
      let route = ([address.host ?? "?"] + job.chain.dropFirst()).joined(separator: " -> ")
      print("\(name): User-Agent \"\(agent)\"")
      print("  answer \(job.status) (206 means the range was honoured), \(job.data.count) bytes")
      print("  host after redirects: \(job.finalURL?.host ?? "unknown")   (path: \(route) -> \(job.finalURL?.host ?? "?"))")
      print("  type: \(job.headers["content-type"] ?? "?"), length of the whole file: \(job.headers["content-range"] ?? job.headers["content-length"] ?? "?")")
      print("  ID3 tag: \(parse.tagBytes) bytes, \(parse.frames.count) MP3 frames = \(seconds(parse.seconds)), \(parse.bitrate / 1000) kbps, \(parse.skippedBytes) stray bytes")
      copies.append((job, parse))
    }
    let a = copies[0].parse
    let b = copies[1].parse
    print("")
    guard !a.frames.isEmpty, !b.frames.isEmpty else {
      print("No MP3 frames in one of the copies (it may not be an MP3, or the host sent a page).")
      return 1
    }
    if copies[0].job.data == copies[1].job.data {
      print("The two copies are byte for byte the same: this host gave both listeners the same file.")
      return 0
    }
    let result = FrameAlign.align(a.frames.map(\.hash), b.frames.map(\.hash))
    let percent = Double(result.matched) / Double(min(a.frames.count, b.frames.count)) * 100
    print("Frames that are byte-identical in both copies, in the same order: \(result.matched) (\(Int(percent.rounded())) % of the shorter copy)")
    if result.differing.isEmpty {
      print("Ranges that differ and then join again: none.")
    } else {
      print("Ranges that differ and then join again (candidate inserted ads):")
      for range in result.differing {
        let aTimes = times(a, range.a)
        let bTimes = times(b, range.b)
        print("  copy A \(aTimes), copy B \(bTimes)")
      }
    }
    if result.unmatchedTailA > 0 || result.unmatchedTailB > 0 {
      print("After the last join: \(result.unmatchedTailA) frames of A and \(result.unmatchedTailB) of B match nothing (the copies had not joined again within 3 MB).")
    }
    print("")
    print(verdict(result: result, a: a, b: b))
    return 0
  }

  static func times(_ parse: MP3Parse, _ range: Range<Int>) -> String {
    guard !range.isEmpty else { return "nothing" }
    let start = parse.frames[range.lowerBound].start
    let last = parse.frames[range.upperBound - 1]
    return "\(seconds(start)) to \(seconds(last.start + last.duration)) (\(String(format: "%.1f", last.start + last.duration - start)) s)"
  }

  static func verdict(result: FrameAlignment, a: MP3Parse, b: MP3Parse) -> String {
    let percent = Double(result.matched) / Double(min(a.frames.count, b.frames.count))
    if result.matched == 0 {
      return "What it means: the copies share no frame, so the host re-encodes the episode for each download, or sent two different files. Byte comparison cannot work on this host."
    }
    if result.differing.isEmpty && percent > 0.99 {
      return "What it means: the same file twice. Either this host inserts nothing here (or gave both listeners the same ads), or the ads were the same for both User-Agents."
    }
    if result.differing.isEmpty {
      return "What it means: the copies agree at the start and then stop agreeing without joining again. Ads may differ, but the 3 MB cut ends before they join, so no range can be named."
    }
    return "What it means: the show's own frames are byte-identical outside the ranges above (\(Int((percent * 100).rounded())) % of the shorter copy), and the ranges are where the host put different audio in each copy. Those are candidate inserted ads; check by listening to the file at those times."
  }
}
