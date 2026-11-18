// LOFI-FORK: filing a finished download (see FORK.md).
import Foundation

extension DownloadStore {
  /// Hashes a finished staged file and files it as `<root>/<episodeId>/<sha256>.<ext>`, marking
  /// the episode downloaded. The downloader and the player that plays a download as it
  /// arrives both file their finished file this way. The entry must still exist (an episode
  /// removed meanwhile is not brought back and `DownloadError.noEntry` is thrown). A staged
  /// file that cannot be read is deleted.
  @discardableResult
  public func installStaged(_ staged: URL, episodeId: String, fileExtension: String) throws
    -> DownloadEntry
  {
    let hash: String
    let bytes: Int64
    do {
      hash = try FileHash.sha256(of: staged)
      bytes = (try FileManager.default.attributesOfItem(atPath: staged.path)[.size] as? Int64) ?? 0
    } catch {
      try? FileManager.default.removeItem(at: staged)
      throw error
    }
    return try install(
      episodeId: episodeId, staged: staged, sha256: hash, fileExtension: fileExtension,
      bytes: bytes, requireEntry: true)
  }
}
