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
    var launchAtLoginMenuItem: NSMenuItem!
    private var hotKeyRefs: [EventHotKeyRef] = []

    override init() {
        super.init()
        setupStatusItem()
        setupMenu()
        setupGlobalHotkeys()
        setupLaunchAtLoginInitialState()
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
        
        button.toolTip = "QuickCapture\n• Left-click or ⌥S: Quick Capture to Clipboard\n• ⇧⌘S or ⇧⌥S: Capture & Annotate\n• Right-click: Menu"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func setupMenu() {
        menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "QuickCapture", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let clipboardItem = NSMenuItem(title: "Capture to Clipboard (Option+S)", action: #selector(captureToClipboardAction), keyEquivalent: "s")
        clipboardItem.keyEquivalentModifierMask = [.option]
        clipboardItem.target = self
        menu.addItem(clipboardItem)

        let annotateItem = NSMenuItem(title: "Capture & Annotate... (⇧⌘S / ⇧⌥S)", action: #selector(captureAndAnnotateAction), keyEquivalent: "s")
        annotateItem.keyEquivalentModifierMask = [.command, .shift]
        annotateItem.target = self
        menu.addItem(annotateItem)
        
        menu.addItem(NSMenuItem.separator())
        
        launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        updateLaunchAtLoginMenuItemState()
        menu.addItem(launchAtLoginMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit QuickCapture", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
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

    func setupGlobalHotkeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                guard let event = theEvent else {
                    ScreenCaptureEngine.shared.captureToClipboard()
                    return noErr
                }
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr && (hotKeyID.id == 2 || hotKeyID.id == 3) {
                    ScreenCaptureEngine.shared.captureForAnnotation()
                } else {
                    ScreenCaptureEngine.shared.captureToClipboard()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
        
        // 1. Option + S (⌥ + S) -> Capture to Clipboard
        var hotKeyID1 = EventHotKeyID(signature: OSType(0x514B31), id: 1)
        var hotKeyRef1: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(optionKey), hotKeyID1, GetEventDispatcherTarget(), 0, &hotKeyRef1)
        if let ref = hotKeyRef1 { hotKeyRefs.append(ref) }
        
        // 2. Command + Shift + S (⌘ + ⇧ + S) -> Capture for Annotation
        var hotKeyID2 = EventHotKeyID(signature: OSType(0x514B32), id: 2)
        var hotKeyRef2: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(cmdKey | shiftKey), hotKeyID2, GetEventDispatcherTarget(), 0, &hotKeyRef2)
        if let ref = hotKeyRef2 { hotKeyRefs.append(ref) }

        // 3. Option + Shift + S (⌥ + ⇧ + S) -> Capture for Annotation
        var hotKeyID3 = EventHotKeyID(signature: OSType(0x514B33), id: 3)
        var hotKeyRef3: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(optionKey | shiftKey), hotKeyID3, GetEventDispatcherTarget(), 0, &hotKeyRef3)
        if let ref = hotKeyRef3 { hotKeyRefs.append(ref) }
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

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
