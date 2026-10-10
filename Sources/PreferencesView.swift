import SwiftUI
import Carbon
import ServiceManagement

struct ShortcutRecorderButton: View {
    let title: String
    let hotkey: HotkeyItem
    let onShortcutRecorded: (HotkeyItem) -> Void

    @State private var isRecording: Bool = false
    @State private var monitor: Any?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                HStack(spacing: 6) {
                    if isRecording {
                        Image(systemName: "record.circle.fill")
                            .foregroundColor(.red)
                            .imageScale(.small)
                        Text("Press keys...")
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    } else {
                        Image(systemName: "keyboard")
                            .foregroundColor(.secondary)
                            .imageScale(.small)
                        Text(hotkey.displayString)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isRecording ? 1.5 : 1)
                )
            }
            .buttonStyle(.plain)

            if let error = errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        errorMessage = nil
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Cancel on Escape
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
            if flags.isEmpty {
                errorMessage = "Hold at least one modifier key (⌘, ⌥, ⇧, ⌃)"
                return nil
            }

            var carbonMods: UInt32 = 0
            if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
            if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
            if flags.contains(.control) { carbonMods |= UInt32(controlKey) }

            let newItem = HotkeyItem(keyCode: UInt32(event.keyCode), modifiers: carbonMods)
            onShortcutRecorded(newItem)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var hotkeyManager = HotkeyManager.shared
    @State private var launchAtLogin: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                Image(systemName: "camera.viewfinder")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("QuickCapture Settings")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Configure keyboard shortcuts and app behavior")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Group: Keyboard Shortcuts
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Keyboard Shortcuts", systemImage: "command")
                            .font(.headline)
                            .foregroundColor(.primary)

                        VStack(spacing: 12) {
                            // 1. Capture to Clipboard
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Capture to Clipboard")
                                        .fontWeight(.medium)
                                    Text("Select area and copy screenshot directly to clipboard")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                ShortcutRecorderButton(
                                    title: "Capture to Clipboard",
                                    hotkey: hotkeyManager.clipboardHotkey
                                ) { newItem in
                                    hotkeyManager.updateClipboardHotkey(newItem)
                                }
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            .cornerRadius(8)

                            // 2. Capture & Annotate
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Capture & Annotate")
                                        .fontWeight(.medium)
                                    Text("Select area and open drawing & annotation editor")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                ShortcutRecorderButton(
                                    title: "Capture & Annotate",
                                    hotkey: hotkeyManager.annotateHotkey
                                ) { newItem in
                                    hotkeyManager.updateAnnotateHotkey(newItem)
                                }
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            .cornerRadius(8)
                        }

                        HStack {
                            Text("Click a shortcut pill and press your desired key combination to record.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Reset to Defaults") {
                                hotkeyManager.resetToDefaults()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )

                    // Group: System & Startup
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Startup", systemImage: "gearshape")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Toggle(isOn: $launchAtLogin) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Launch at Login")
                                    .fontWeight(.medium)
                                Text("Start QuickCapture helper automatically when you log into macOS")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onChange(of: launchAtLogin) { newValue in
                            updateLaunchAtLogin(newValue)
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                    .padding(16)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )

                    // Group: About
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("QuickCapture v1.1")
                                .font(.footnote)
                                .fontWeight(.semibold)
                            Text("Native macOS screenshot utility with instant annotation.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                }
                .padding(24)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Done") {
                    PreferencesWindowManager.shared.close()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 520, height: 500)
        .onAppear {
            checkLaunchAtLoginStatus()
        }
    }

    private func checkLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    private func updateLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable && SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                } else if !enable && SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("[QuickCapture] Error setting launch at login: \(error)")
            }
        }
    }
}
