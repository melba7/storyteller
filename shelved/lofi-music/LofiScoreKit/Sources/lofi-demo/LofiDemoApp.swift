// The demo as a macOS app: `swift run -c release lofi-demo` (or open Package.swift in
// Xcode and run the lofi-demo scheme). Release matters: the first launch synthesises the
// placeholder tracks, which takes seconds optimised and minutes in a debug build.
// For iPhone, open Demo/LofiScoreDemo.xcodeproj instead.

#if canImport(SwiftUI) && os(macOS)
import AppKit
import LofiDemoKit
import SwiftUI

final class DemoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A SwiftPM executable starts as a background process; make it a normal app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct LofiDemoApp: App {
    @NSApplicationDelegateAdaptor(DemoAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("LofiScore Demo") {
            DemoRootView()
        }
    }
}
#else
import Foundation

@main
enum LofiDemoUnavailable {
    static func main() {
        print("lofi-demo needs macOS. On iPhone, open Demo/LofiScoreDemo.xcodeproj. Here, try `swift test` or `swift run lofi-replay --synthetic`.")
    }
}
#endif
