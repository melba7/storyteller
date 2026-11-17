// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The main colour of a show's artwork, which tints the full-screen player's background.

import CoreImage
import Foundation
import UIKit

/// The average colour of the picture at `url` as "#rrggbb", or nil when it can't be
/// downloaded or read. Works on a small thumbnail, so a large picture costs little.
func artworkColor(_ url: URL) async -> String? {
  guard let data = await ArtworkLoader.data(url), let image = UIImage(data: data),
    let source = CIImage(image: image)
  else { return nil }
  let extent = source.extent
  guard extent.width > 0, extent.height > 0, extent.width.isFinite, extent.height.isFinite else {
    return nil
  }
  // Shrink first (the average of a thumbnail is the picture's average, near enough).
  let scale = min(1, 64 / max(extent.width, extent.height))
  let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
  let filter = CIFilter(
    name: "CIAreaAverage",
    parameters: [kCIInputImageKey: small, kCIInputExtentKey: CIVector(cgRect: small.extent)])
  guard let output = filter?.outputImage else { return nil }
  var pixel = [UInt8](repeating: 0, count: 4)
  let context = CIContext(options: [.workingColorSpace: NSNull()])
  context.render(
    output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
    format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
  return String(format: "#%02x%02x%02x", pixel[0], pixel[1], pixel[2])
}
