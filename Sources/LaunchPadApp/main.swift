import Foundation
import AppKit
import LaunchPad

// LaunchPad App Entry Point
// Build: swift build -c release --product LaunchPadApp
// Bundle: create .app with Info.plist

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
