// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The system's AirPlay button as a view for the player screen. Tapping it opens iOS's own list
// of speakers and headphones; the choice moves the podcast's sound there with no code of ours.

import AVKit
import ExpoModulesCore
import UIKit

final class AirPlayRouteView: ExpoView {
  private let picker = AVRoutePickerView()

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    backgroundColor = .clear
    picker.backgroundColor = .clear
    // The player's background is dark, so the button is white.
    picker.tintColor = .white
    picker.activeTintColor = .white
    picker.prioritizesVideoDevices = false
    addSubview(picker)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    picker.frame = bounds
  }

  /// True on a light sheet, so the button is dark; false (the start) is the white one.
  func setLight(_ light: Bool) {
    picker.tintColor = light ? .black : .white
    picker.activeTintColor = light ? .black : .white
  }

  /// What VoiceOver says for the button.
  func setLabel(_ label: String) {
    picker.accessibilityLabel = label
  }
}
