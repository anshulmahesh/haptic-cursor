import Cocoa
import SwiftUI

final class HapticProfilerAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let engine = HapticEngine()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        let controller = NSHostingController(rootView: HapticProfilerView(engine: engine))
        let newWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 830, height: 685),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                 backing: .buffered, defer: false)
        newWindow.title = "Menu Magnet Haptic Profiler"
        newWindow.minSize = NSSize(width: 670, height: 470)
        newWindow.contentViewController = controller
        newWindow.center()
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
        engine.start()
    }

    func windowWillClose(_ notification: Notification) {
        engine.stop()
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { engine.stop() }
}

@main
struct HapticProfilerMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = HapticProfilerAppDelegate()
        app.delegate = delegate
        app.run()
    }
}
