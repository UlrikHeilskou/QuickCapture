import Cocoa
import Carbon
import Combine

struct HotkeyItem: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier bits: cmdKey, optionKey, shiftKey, controlKey

    var displayString: String {
        var str = ""
        if (modifiers & UInt32(controlKey)) != 0 { str += "⌃" }
        if (modifiers & UInt32(optionKey)) != 0 { str += "⌥" }
        if (modifiers & UInt32(shiftKey)) != 0 { str += "⇧" }
        if (modifiers & UInt32(cmdKey)) != 0 { str += "⌘" }
        str += HotkeyManager.stringForKeyCode(UInt16(keyCode))
        return str
    }

    var keyEquivalent: String {
        return HotkeyManager.stringForKeyCode(UInt16(keyCode)).lowercased()
    }

    var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if (modifiers & UInt32(controlKey)) != 0 { flags.insert(.control) }
        if (modifiers & UInt32(optionKey)) != 0 { flags.insert(.option) }
        if (modifiers & UInt32(shiftKey)) != 0 { flags.insert(.shift) }
        if (modifiers & UInt32(cmdKey)) != 0 { flags.insert(.command) }
        return flags
    }
}

final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    @Published var clipboardHotkey: HotkeyItem
    @Published var annotateHotkey: HotkeyItem

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var isHandlerInstalled = false

    private let clipboardKeyPref = "QuickCapture_Hotkey_Clipboard"
    private let annotateKeyPref = "QuickCapture_Hotkey_Annotate"

    static let defaultClipboardHotkey = HotkeyItem(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey)) // ⌥S
    static let defaultAnnotateHotkey = HotkeyItem(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | shiftKey)) // ⇧⌘S

    var onHotkeysChanged: (() -> Void)?

    private init() {
        // Load saved or defaults
        if let data = UserDefaults.standard.data(forKey: clipboardKeyPref),
           let saved = try? JSONDecoder().decode(HotkeyItem.self, from: data) {
            self.clipboardHotkey = saved
        } else {
            self.clipboardHotkey = Self.defaultClipboardHotkey
        }

        if let data = UserDefaults.standard.data(forKey: annotateKeyPref),
           let saved = try? JSONDecoder().decode(HotkeyItem.self, from: data) {
            self.annotateHotkey = saved
        } else {
            self.annotateHotkey = Self.defaultAnnotateHotkey
        }
    }

    func updateClipboardHotkey(_ item: HotkeyItem) {
        clipboardHotkey = item
        save()
        registerAll()
        onHotkeysChanged?()
    }

    func updateAnnotateHotkey(_ item: HotkeyItem) {
        annotateHotkey = item
        save()
        registerAll()
        onHotkeysChanged?()
    }

    func resetToDefaults() {
        clipboardHotkey = Self.defaultClipboardHotkey
        annotateHotkey = Self.defaultAnnotateHotkey
        save()
        registerAll()
        onHotkeysChanged?()
    }

    private func save() {
        if let data1 = try? JSONEncoder().encode(clipboardHotkey) {
            UserDefaults.standard.set(data1, forKey: clipboardKeyPref)
        }
        if let data2 = try? JSONEncoder().encode(annotateHotkey) {
            UserDefaults.standard.set(data2, forKey: annotateKeyPref)
        }
    }

    func registerAll() {
        installHandlerIfNeeded()

        // Unregister existing
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        // Register Clipboard (ID: 1)
        let hotKeyID1 = EventHotKeyID(signature: OSType(0x514B31), id: 1)
        var hotKeyRef1: EventHotKeyRef?
        RegisterEventHotKey(
            clipboardHotkey.keyCode,
            clipboardHotkey.modifiers,
            hotKeyID1,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef1
        )
        if let ref = hotKeyRef1 { hotKeyRefs.append(ref) }

        // Register Annotate (ID: 2)
        let hotKeyID2 = EventHotKeyID(signature: OSType(0x514B32), id: 2)
        var hotKeyRef2: EventHotKeyRef?
        RegisterEventHotKey(
            annotateHotkey.keyCode,
            annotateHotkey.modifiers,
            hotKeyID2,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef2
        )
        if let ref = hotKeyRef2 { hotKeyRefs.append(ref) }
    }

    private func installHandlerIfNeeded() {
        guard !isHandlerInstalled else { return }
        isHandlerInstalled = true

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                guard let event = theEvent else { return noErr }
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr {
                    DispatchQueue.main.async {
                        HotkeyManager.shared.handleHotKey(id: hotKeyID.id)
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }

    func handleHotKey(id: UInt32) {
        if id == 1 {
            ScreenCaptureEngine.shared.captureToClipboard()
        } else if id == 2 {
            ScreenCaptureEngine.shared.captureForAnnotation()
        }
    }

    static func stringForKeyCode(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: break
        }

        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return fallbackKeyName(keyCode)
        }
        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        guard let bytePtr = CFDataGetBytePtr(dataRef) else {
            return fallbackKeyName(keyCode)
        }
        let keyLayout = bytePtr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 }

        var keysDown: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0
        let status = UCKeyTranslate(
            keyLayout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &keysDown,
            chars.count,
            &length,
            &chars
        )
        if status == noErr && length > 0 {
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
        return fallbackKeyName(keyCode)
    }

    private static func fallbackKeyName(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        default: return "Key(\(keyCode))"
        }
    }
}
