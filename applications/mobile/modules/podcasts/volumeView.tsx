// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The system volume slider, a native view of the podcasts module (VolumeSliderView.swift).
// Only on iOS, where the module exists. Not imported by any test, because the native view is
// not there.
import { requireNativeViewManager } from "expo-modules-core"
import type { ComponentType } from "react"
import type { StyleProp, ViewStyle } from "react-native"

import { Podcasts } from "./index"

type VolumeViewProps = {
  /** True on a light sheet, so the slider is dark. */
  light: boolean
  /** What VoiceOver says for the slider. */
  label: string
  style?: StyleProp<ViewStyle>
}

/** The volume slider, or null where the native module is missing (Android, the web). */
export const VolumeView: ComponentType<VolumeViewProps> | null =
  Podcasts === null ? null : requireNativeViewManager("PodcastsVolume")
