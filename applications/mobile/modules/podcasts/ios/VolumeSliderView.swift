// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The system volume slider for the player screen: an MPVolumeView, which moves the phone's
// own volume (the same as the volume buttons) with no code of ours. Its track is drawn as a
// thick rounded bar like the scrubber (a light fill on a darker track, no visible thumb), with
// images drawn here in the sheet's colours.

import ExpoModulesCore
import MediaPlayer
import UIKit

final class VolumeSliderView: ExpoView {
  private let slider = MPVolumeView(frame: .zero)
  /// The bar's thickness in points, the same as the scrubber's.
  private static let barHeight: CGFloat = 7
  /// The thumb can't be seen, but a slider is grabbed by its thumb, so it is as wide as a
  /// fingertip (the system thumb's size).
  private static let thumbWidth: CGFloat = 28
  private var fillColor: UIColor?
  private var trackColor: UIColor?

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    backgroundColor = .clear
    slider.backgroundColor = .clear
    // The AirPlay button has its own place in the player, so the slider is only the slider.
    slider.showsRouteButton = false
    // The slider reaches past both edges (see layoutSubviews); those parts are cut off.
    clipsToBounds = true
    addSubview(slider)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // The slider draws itself 40 points high: keep it centred in whatever height it is given.
    // A thumb stops half its width inside each end of a slider, so the slider reaches that far
    // past this view's edges: the fill then runs from edge to edge, none at zero volume and
    // all of the bar at full volume.
    let height = slider.sizeThatFits(bounds.size).height
    let reach = Self.thumbWidth / 2
    slider.frame = CGRect(
      x: -reach, y: (bounds.height - height) / 2, width: bounds.width + 2 * reach,
      height: height)
  }

  /// True on a light sheet (a dark slider), false on a dark one (a light slider).
  func setLight(_ light: Bool) {
    slider.overrideUserInterfaceStyle = light ? .light : .dark
    slider.tintColor = light ? .black : .white
  }

  /// The colour of the part up to the volume (a "#rrggbb" string from JavaScript).
  func setFill(_ color: UIColor?) {
    fillColor = color
    applyBar()
  }

  /// The colour of the rest of the bar.
  func setTrack(_ color: UIColor?) {
    trackColor = color
    applyBar()
  }

  /// Draws the bar: rounded images that stretch with the slider, and a thumb you can't see.
  private func applyBar() {
    guard let fillColor, let trackColor else { return }
    slider.setMinimumVolumeSliderImage(Self.barImage(fillColor, clearBefore: true), for: .normal)
    slider.setMaximumVolumeSliderImage(Self.barImage(trackColor, clearBefore: false), for: .normal)
    slider.setVolumeThumbImage(Self.clearImage(), for: .normal)
  }

  /// A fully rounded bar, one point wider than it is tall, stretched by its middle column. The
  /// part of the slider past this view's edge gets clear space: before the fill's bar
  /// (`clearBefore`) or after the track's, so both bars end with a rounded cap at the edges.
  private static func barImage(_ color: UIColor, clearBefore: Bool) -> UIImage {
    let height = barHeight
    let clear = thumbWidth / 2
    let size = CGSize(width: clear + height + 1, height: height)
    let bar = CGRect(x: clearBefore ? clear : 0, y: 0, width: height + 1, height: height)
    let image = UIGraphicsImageRenderer(size: size).image { _ in
      color.setFill()
      UIBezierPath(roundedRect: bar, cornerRadius: height / 2).fill()
    }
    let cap = height / 2
    let caps =
      clearBefore
      ? UIEdgeInsets(top: 0, left: clear + cap, bottom: 0, right: cap)
      : UIEdgeInsets(top: 0, left: cap, bottom: 0, right: clear + cap)
    return image.resizableImage(withCapInsets: caps, resizingMode: .stretch)
  }

  /// An image with nothing in it, for the thumb: a fingertip wide, so it is easy to grab.
  private static func clearImage() -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: thumbWidth, height: thumbWidth)).image { _ in }
  }

  /// What VoiceOver says for the slider.
  func setLabel(_ label: String) {
    slider.accessibilityLabel = label
  }
}
