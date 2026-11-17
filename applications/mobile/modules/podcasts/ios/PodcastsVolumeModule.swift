// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The player's volume slider as a native view (see VolumeSliderView). It is a module of its
// own because an Expo module can have only one native view, and the AirPlay button already
// takes the "Podcasts" module's.

import ExpoModulesCore

public class PodcastsVolumeModule: Module {
  public func definition() -> ModuleDefinition {
    Name("PodcastsVolume")

    View(VolumeSliderView.self) {
      Prop("light") { (view: VolumeSliderView, light: Bool) in view.setLight(light) }
      Prop("label") { (view: VolumeSliderView, label: String) in view.setLabel(label) }
    }
  }
}
