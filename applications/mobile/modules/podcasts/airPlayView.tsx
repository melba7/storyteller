// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The system's AirPlay button, a native view of the podcasts module (AirPlayRouteView.swift).
// Only on iOS, where the module exists. Not imported by any test, because the native view is
// not there.
import { requireNativeViewManager } from "expo-modules-core"
import type { ComponentType } from "react"
import type { StyleProp, ViewStyle } from "react-native"

import { Podcasts } from "./index"

type AirPlayViewProps = {
  /** What VoiceOver says for the button. */
  label: string
  /** True on a light sheet, so the button is dark (white when left out). */
  light?: boolean
  style?: StyleProp<ViewStyle>
}

/** The AirPlay button, or null where the native module is missing (Android, the web). */
export const AirPlayView: ComponentType<AirPlayViewProps> | null =
  Podcasts === null ? null : requireNativeViewManager("Podcasts")
