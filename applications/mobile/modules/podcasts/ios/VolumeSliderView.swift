// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The system volume slider for the player screen: an MPVolumeView, which moves the phone's
// own volume (the same as the volume buttons) with no code of ours.

import ExpoModulesCore
import MediaPlayer
import UIKit

final class VolumeSliderView: ExpoView {
  private let slider = MPVolumeView(frame: .zero)

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    backgroundColor = .clear
    slider.backgroundColor = .clear
    // The AirPlay button has its own place in the player, so the slider is only the slider.
    slider.showsRouteButton = false
    addSubview(slider)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // The slider draws itself 40 points high: keep it centred in whatever height it is given.
    let height = slider.sizeThatFits(bounds.size).height
    slider.frame = CGRect(
      x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
  }

  /// True on a light sheet (a dark slider), false on a dark one (a light slider).
  func setLight(_ light: Bool) {
    slider.overrideUserInterfaceStyle = light ? .light : .dark
    slider.tintColor = light ? .black : .white
  }

  /// What VoiceOver says for the slider.
  func setLabel(_ label: String) {
    slider.accessibilityLabel = label
  }
}
