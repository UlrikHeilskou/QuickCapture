import Cocoa
import ServiceManagement
import Carbon

final class ScreenCaptureEngine {
    static let shared = ScreenCaptureEngine()

    private init() {}

    func captureToClipboard() {
        ScreenCaptureOverlayCoordinator.shared.startSelection(mode: .clipboard)
    }

    func captureForAnnotation() {
        ScreenCaptureOverlayCoordinator.shared.startSelection(mode: .annotation)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var clipboardMenuItem: NSMenuItem!
    var annotateMenuItem: NSMenuItem!
    var preferencesMenuItem: NSMenuItem!
    var launchAtLoginMenuItem: NSMenuItem!

    override init() {
        super.init()
        setupStatusItem()
        setupMenu()
        setupHotkeys()
        setupLaunchAtLoginInitialState()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openPreferencesAction),
            name: NSNotification.Name("com.ulrik.QuickCapture.openPreferences"),
            object: nil
        )

        if CommandLine.arguments.contains("--preferences") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                PreferencesWindowManager.shared.showPreferences()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            UpdateManager.shared.checkForUpdates(silent: true)
        }
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem.button else { return }
        button.title = ""
        
        if let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "QuickCapture") {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            let configuredImage = image.withSymbolConfiguration(config) ?? image
            configuredImage.isTemplate = true
            button.image = configuredImage
        }
        
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateTooltipsAndMenu()
    }

    func setupMenu() {
        menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "QuickCapture", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        clipboardMenuItem = NSMenuItem(title: "Capture to Clipboard", action: #selector(captureToClipboardAction), keyEquivalent: "")
        clipboardMenuItem.target = self
        menu.addItem(clipboardMenuItem)

        annotateMenuItem = NSMenuItem(title: "Capture & Annotate...", action: #selector(captureAndAnnotateAction), keyEquivalent: "")
        annotateMenuItem.target = self
        menu.addItem(annotateMenuItem)
        
        menu.addItem(NSMenuItem.separator())

        preferencesMenuItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferencesAction), keyEquivalent: ",")
        preferencesMenuItem.keyEquivalentModifierMask = [.command]
        preferencesMenuItem.target = self
        menu.addItem(preferencesMenuItem)

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesAction), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        
        launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        updateLaunchAtLoginMenuItemState()
        menu.addItem(launchAtLoginMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit QuickCapture", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        updateTooltipsAndMenu()
    }

    func updateTooltipsAndMenu() {
        let clip = HotkeyManager.shared.clipboardHotkey
        let annot = HotkeyManager.shared.annotateHotkey

        if let clipboardMenuItem = clipboardMenuItem {
            clipboardMenuItem.title = "Capture to Clipboard (\(clip.displayString))"
            clipboardMenuItem.keyEquivalent = clip.keyEquivalent
            clipboardMenuItem.keyEquivalentModifierMask = clip.keyEquivalentModifierMask
        }

        if let annotateMenuItem = annotateMenuItem {
            annotateMenuItem.title = "Capture & Annotate... (\(annot.displayString))"
            annotateMenuItem.keyEquivalent = annot.keyEquivalent
            annotateMenuItem.keyEquivalentModifierMask = annot.keyEquivalentModifierMask
        }

        if let button = statusItem?.button {
            button.toolTip = "QuickCapture\n• Left-click or \(clip.displayString): Quick Capture to Clipboard\n• \(annot.displayString): Capture & Annotate\n• Right-click: Menu"
        }
    }

    func setupHotkeys() {
        HotkeyManager.shared.onHotkeysChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.updateTooltipsAndMenu()
            }
        }
        HotkeyManager.shared.registerAll()
    }

    @objc func openPreferencesAction() {
        PreferencesWindowManager.shared.showPreferences()
    }

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            ScreenCaptureEngine.shared.captureToClipboard()
            return
        }
        
        if event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            updateLaunchAtLoginMenuItemState()
            statusItem.popUpMenu(menu)
        } else {
            ScreenCaptureEngine.shared.captureToClipboard()
        }
    }

    @objc func captureToClipboardAction() {
        ScreenCaptureEngine.shared.captureToClipboard()
    }

    @objc func captureAndAnnotateAction() {
        ScreenCaptureEngine.shared.captureForAnnotation()
    }

    @objc func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                NSLog("[QuickCapture] Toggle launch at login error: \(error)")
            }
        }
        updateLaunchAtLoginMenuItemState()
    }

    func updateLaunchAtLoginMenuItemState() {
        if #available(macOS 13.0, *) {
            let isEnabled = SMAppService.mainApp.status == .enabled
            launchAtLoginMenuItem.state = isEnabled ? .on : .off
        } else {
            launchAtLoginMenuItem.isEnabled = false
        }
    }

    func setupLaunchAtLoginInitialState() {
        let hasConfigured = UserDefaults.standard.bool(forKey: "QuickCapture_ConfiguredLogin")
        if !hasConfigured {
            UserDefaults.standard.set(true, forKey: "QuickCapture_ConfiguredLogin")
            if #available(macOS 13.0, *) {
                if SMAppService.mainApp.status != .enabled {
                    try? SMAppService.mainApp.register()
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PreferencesWindowManager.shared.showPreferences()
        return true
    }

    @objc func checkForUpdatesAction() {
        PreferencesWindowManager.shared.showPreferences()
        UpdateManager.shared.checkForUpdates(silent: false)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--preferences") {
            PreferencesWindowManager.shared.showPreferences()
        }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openPreferencesAction),
            name: NSNotification.Name("com.ulrik.QuickCapture.openPreferences"),
            object: nil
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            UpdateManager.shared.checkForUpdates(silent: true)
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
