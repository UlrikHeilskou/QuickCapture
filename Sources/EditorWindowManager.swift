import Cocoa
import SwiftUI

final class EditorWindowManager: NSObject, NSWindowDelegate {
    static let shared = EditorWindowManager()

    var windowController: NSWindowController?
    private var tempFileURL: URL?

    private let widthKey = "QuickCapture_EditorWindow_Width"
    private let heightKey = "QuickCapture_EditorWindow_Height"

    private override init() {
        super.init()
    }

    func openEditor(with image: NSImage, tempURL: URL?) {
        self.tempFileURL = tempURL

        // Close any existing editor window
        closeEditor()

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
        
        let savedWidth = UserDefaults.standard.double(forKey: widthKey)
        let savedHeight = UserDefaults.standard.double(forKey: heightKey)

        var desiredWidth: CGFloat
        var desiredHeight: CGFloat

        if savedWidth >= 500 && savedHeight >= 350 {
            // Restore user's customized size
            desiredWidth = min(CGFloat(savedWidth), screenFrame.width * 0.98)
            desiredHeight = min(CGFloat(savedHeight), screenFrame.height * 0.98)
        } else {
            // Smart initial size fitting the captured image comfortably
            let idealWidth = image.size.width + 60
            let idealHeight = image.size.height + 140
            desiredWidth = max(800, min(idealWidth, screenFrame.width * 0.85))
            desiredHeight = max(560, min(idealHeight, screenFrame.height * 0.85))
        }

        let initialX = (screenFrame.width - desiredWidth) / 2 + screenFrame.minX
        let initialY = (screenFrame.height - desiredHeight) / 2 + screenFrame.minY
        let targetFrame = NSRect(x: initialX, y: initialY, width: desiredWidth, height: desiredHeight)

        let window = NSWindow(
            contentRect: targetFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "QuickCapture - Drawing & Annotation Editor"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 550, height: 380)
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let rootView = DrawingEditorView(
            originalImage: image,
            onDismiss: { [weak self] in
                self?.closeEditor()
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController

        // Force the window frame and content size AFTER assigning contentViewController
        window.setFrame(targetFrame, display: true, animate: false)
        window.setContentSize(NSSize(width: desiredWidth, height: desiredHeight))

        let wc = NSWindowController(window: window)
        self.windowController = wc

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    func closeEditor() {
        if let wc = windowController, let win = wc.window {
            saveCurrentWindowSize(win.frame.size)
            win.close()
            windowController = nil
        }

        if let tempURL = tempFileURL {
            try? FileManager.default.removeItem(at: tempURL)
            tempFileURL = nil
        }

        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            saveCurrentWindowSize(window.frame.size)
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            saveCurrentWindowSize(window.frame.size)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            saveCurrentWindowSize(window.frame.size)
        }

        if let tempURL = tempFileURL {
            try? FileManager.default.removeItem(at: tempURL)
            tempFileURL = nil
        }
        windowController = nil
        NSApp.setActivationPolicy(.accessory)
    }

    private func saveCurrentWindowSize(_ size: CGSize) {
        guard size.width >= 500 && size.height >= 350 else { return }
        UserDefaults.standard.set(Double(size.width), forKey: widthKey)
        UserDefaults.standard.set(Double(size.height), forKey: heightKey)
        UserDefaults.standard.synchronize()
    }
}
