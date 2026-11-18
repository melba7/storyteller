// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// PodcastStreamDownload's side that answers the player: AVFoundation's byte-range requests are
// answered from the file as far as it has arrived, a turn's worth at a time, and the rest wait.
// Runs on the loader's queue, like the rest of the class.

import AVFoundation
import Foundation
import PodcastDownloads

extension PodcastStreamDownload {
  // MARK: Answering the player

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
  ) -> Bool {
    guard !stopped else { return false }
    switch answer(loadingRequest) {
    case .finished: break
    case .waiting: pending.append(loadingRequest)
    case .more:
      pending.append(loadingRequest)
      serveLater()
    }
    return true
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest
  ) {
    pending.removeAll { $0 === loadingRequest }
  }

  /// Answers every waiting request as far as the file allows, one turn's worth each.
  func serve() {
    var more = false
    pending = pending.filter { request in
      guard !request.isCancelled, !request.isFinished else { return false }
      switch answer(request) {
      case .finished: return false
      case .waiting: return true
      case .more:
        more = true
        return true
      }
    }
    if more { serveLater() }
  }

  /// Serves again in the next turn of the queue, after any cancel the player sent meanwhile.
  func serveLater() {
    guard !serveScheduled else { return }
    serveScheduled = true
    queue.async {
      self.serveScheduled = false
      if !self.stopped { self.serve() }
    }
  }

  enum Answer {
    /// Done or failed: the request is no longer kept.
    case finished
    /// Waits for bytes that have not arrived.
    case waiting
    /// Has more bytes on disk to hand over in the next turn.
    case more
  }

  /// Hands over what can be handed over now, at most `perTurn` bytes.
  private func answer(_ request: AVAssetResourceLoadingRequest) -> Answer {
    if let info = request.contentInformationRequest {
      if let contentType, let expected {
        info.contentType = contentType
        info.contentLength = expected
        info.isByteRangeAccessSupported = true
      } else if let failure {
        request.finishLoading(with: failure)
        return .finished
      } else {
        // The length is not known yet; it is when the response says so, or the download ends.
        return .waiting
      }
    }
    guard let data = request.dataRequest else {
      request.finishLoading()
      return .finished
    }
    guard let reader else {
      request.finishLoading(with: failure ?? PodcastFetchError(message: "The download was stopped."))
      return .finished
    }
    var handed: Int64 = 0
    do {
      while true {
        guard !request.isCancelled else { return .finished }
        let wanted: Int64? =
          data.requestsAllDataToEndOfResource
          ? nil : max(0, data.requestedOffset + Int64(data.requestedLength) - data.currentOffset)
        let slice = StreamRules.answerable(
          offset: data.currentOffset, length: wanted, available: available, expected: expected)
        if slice.length > 0 {
          if handed >= Self.perTurn { return .more }
          try reader.seek(toOffset: UInt64(slice.offset))
          guard let bytes = try reader.read(upToCount: Int(min(slice.length, Self.chunk))),
            !bytes.isEmpty
          else { throw PodcastFetchError(message: "The downloaded part couldn't be read.") }
          data.respond(with: bytes)
          handed += Int64(bytes.count)
          continue
        }
        if slice.complete {
          request.finishLoading()
          return .finished
        }
        if let failure {
          request.finishLoading(with: failure)
          return .finished
        }
        return .waiting
      }
    } catch {
      request.finishLoading(with: error)
      return .finished
    }
  }
}
