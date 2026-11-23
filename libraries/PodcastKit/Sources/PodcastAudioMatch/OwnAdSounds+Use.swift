// LOFI-FORK: which of the phone's own sounds are scanned for, and which hits are trusted (see FORK.md).
import Foundation

extension OwnAdSounds {
  /// How long the matching of one anchor covers: an anchor is every eighth frame, and a frame
  /// of the usual MP3 (44.1 kHz) lasts 1152 / 44100 seconds. About 0.21 seconds.
  static let anchorSeconds = Double(AdSoundLibrary.step) * 1152 / 44_100

  /// The sounds to scan an episode of `show` with: the prints learned in that show, and those
  /// seen twice or more, which may cross shows. The remembered ads of `KnownAds` match only in
  /// their own show, and a print seen once may be one host's read of one show. The index of a
  /// sound in this library is not its index in `entries`.
  public func library(for show: String) -> AdSoundLibrary {
    AdSoundLibrary(
      sounds: entries.filter { $0.show == show || $0.sound.seen >= 2 }.map(\.sound))
  }

  /// The hits of a scan of the phone's own sounds that are worth skipping. A hit starts where the
  /// whole print would start, also when only a part of it matched (a sting that ends a long print
  /// matches alone and the hit then begins a minute before it), so a hit is kept only when the
  /// anchors that matched cover at least half of its length. A hit that matched all of a print,
  /// or the first part of it (its end is where the matching stopped), is kept; a hit that matched
  /// only the end or the middle of a long print is not. Hits made by hand, with no matched
  /// anchors, and hits that are not times are left out.
  public static func trusted(_ hits: [AdSoundHit]) -> [AdSoundHit] {
    hits.filter { hit in
      let length = hit.end - hit.start
      return hit.matched > 0 && length.isFinite && Double(hit.matched) * anchorSeconds * 2 >= length
    }
  }
}
