import Cocoa
import SwiftUI

final class PreferencesWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PreferencesWindowManager: NSObject, NSWindowDelegate {
    static let shared = PreferencesWindowManager()

    private var windowController: NSWindowController?

    private override init() {
        super.init()
    }

    func showPreferences() {
        if let controller = windowController, let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = PreferencesView()
        let hostingView = FirstMouseHostingView(rootView: contentView)

        let window = PreferencesWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuickCapture Preferences"
        window.contentView = hostingView
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        self.windowController = controller

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        windowController?.window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        windowController = nil
    }
}
