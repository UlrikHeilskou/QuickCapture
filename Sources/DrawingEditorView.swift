import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DrawingEditorView: View {
    let originalImage: NSImage
    let onDismiss: () -> Void

    @State private var elements: [DrawingElement] = []
    @State private var undoStack: [[DrawingElement]] = []
    @State private var redoStack: [[DrawingElement]] = []

    @State private var selectedTool: DrawingTool = .arrow
    @State private var selectedColor: Color = .red
    @State private var selectedStrokeWidth: CGFloat = 4.0

    @State private var currentDrawing: DrawingElement? = nil
    @State private var copySuccessMessage: String? = nil

    private let presetColors: [Color] = [
        .red,
        .orange,
        .yellow,
        .green,
        .blue,
        .purple,
        .white,
        .black
    ]

    private let strokeWidths: [(label: String, width: CGFloat)] = [
        ("Thin", 2.0),
        ("Medium", 4.0),
        ("Thick", 8.0),
        ("Extra", 14.0)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Toolbar
            toolbarHeader
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)

            Divider()

            // MARK: - Canvas Area
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    ZStack {
                        // Background Image
                        Image(nsImage: originalImage)
                            .resizable()
                            .frame(width: originalImage.size.width, height: originalImage.size.height)

                        // Drawing Canvas
                        Canvas { context, _ in
                            for element in elements {
                                DrawingRenderer.drawElement(element, in: &context)
                            }
                            if let current = currentDrawing {
                                DrawingRenderer.drawElement(current, in: &context)
                            }
                        }
                        .frame(width: originalImage.size.width, height: originalImage.size.height)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in
                                    handleDragChanged(value)
                                }
                                .onEnded { value in
                                    handleDragEnded(value)
                                }
                        )
                    }
                    .frame(
                        minWidth: max(geo.size.width, originalImage.size.width),
                        minHeight: max(geo.size.height, originalImage.size.height),
                        alignment: .center
                    )
                }
            }

            Divider()

            // MARK: - Bottom Action Bar
            bottomActionBar
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
        }
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .onAppear {
            setupKeyboardMonitor()
        }
    }

    // MARK: - Toolbar View
    private var toolbarHeader: some View {
        HStack(spacing: 8) {
            // Tool selector
            HStack(spacing: 3) {
                ForEach(DrawingTool.allCases) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tool.iconName)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tool.label)
                                .font(.system(size: 8.5))
                                .lineLimit(1)
                        }
                        .frame(width: 50, height: 34)
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(
                                    selectedTool == tool
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.white.opacity(0.001)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(selectedTool == tool ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: selectedTool == tool ? 1.5 : 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(RoundedRectangle(cornerRadius: 5))
                    .help(tool.label)
                }
            }

            Divider().frame(height: 24)

            // Stroke Width Selector
            Menu {
                ForEach(strokeWidths, id: \.width) { item in
                    Button(action: {
                        selectedStrokeWidth = item.width
                    }) {
                        HStack {
                            Text(item.label)
                            if selectedStrokeWidth == item.width {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: max(3, min(selectedStrokeWidth, 12)), height: max(3, min(selectedStrokeWidth, 12)))
                    Text("\(Int(selectedStrokeWidth)) pt")
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(height: 26)
                .padding(.horizontal, 6)
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .background(Color.gray.opacity(0.15))
                .cornerRadius(5)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .help("Stroke Width")

            Divider().frame(height: 24)

            // Color Palette
            HStack(spacing: 5) {
                ForEach(presetColors, id: \.self) { color in
                    Button {
                        selectedColor = color
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color)
                                .frame(width: 17, height: 17)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.25), lineWidth: 1)
                                )

                            if selectedColor == color {
                                Circle()
                                    .stroke(Color.primary, lineWidth: 2)
                                    .frame(width: 21, height: 21)
                            }
                        }
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                        .background(Color.white.opacity(0.001))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                }

                ColorPicker("", selection: $selectedColor)
                    .labelsHidden()
                    .frame(width: 20, height: 20)
                    .help("Custom Color")
            }

            Spacer()

            // Undo, Redo, Clear
            HStack(spacing: 4) {
                Button {
                    undo()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .medium))
                        Text("Undo")
                            .font(.system(size: 10.5))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(RoundedRectangle(cornerRadius: 5))
                    .background(undoStack.isEmpty ? Color.white.opacity(0.001) : Color.gray.opacity(0.15))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .disabled(undoStack.isEmpty)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo (⌘Z)")

                Button {
                    redo()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 11, weight: .medium))
                        Text("Redo")
                            .font(.system(size: 10.5))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(RoundedRectangle(cornerRadius: 5))
                    .background(redoStack.isEmpty ? Color.white.opacity(0.001) : Color.gray.opacity(0.15))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .disabled(redoStack.isEmpty)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("Redo (⇧⌘Z)")

                Divider().frame(height: 18)

                Button {
                    clearAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(elements.isEmpty ? .secondary : .red)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(elements.isEmpty)
                .help("Clear All Drawings")
            }
        }
    }

    // MARK: - Bottom Action Bar
    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Text("\(Int(originalImage.size.width)) × \(Int(originalImage.size.height)) px")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            if let message = copySuccessMessage {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                }
                .transition(.opacity)
            }

            Spacer()

            Button("Cancel") {
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                saveToFile()
            } label: {
                Label("Save Image...", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .help("Save annotated image to disk (⌘S)")

            Button {
                copyToClipboard()
            } label: {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .help("Copy annotated image to clipboard and close")
        }
    }

    // MARK: - Drag Gesture Handlers
    private func handleDragChanged(_ value: DragGesture.Value) {
        let loc = value.location
        let start = value.startLocation

        if currentDrawing == nil {
            var newElement = DrawingElement(
                tool: selectedTool,
                points: [start, loc],
                startPoint: start,
                endPoint: loc,
                color: selectedColor,
                strokeWidth: selectedStrokeWidth
            )
            if selectedTool == .pen {
                newElement.points = [start, loc]
            }
            currentDrawing = newElement
        } else {
            switch selectedTool {
            case .pen:
                currentDrawing?.points.append(loc)
            case .line, .arrow, .rectangle, .filledRectangle, .circle, .filledCircle:
                currentDrawing?.endPoint = loc
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        guard var drawing = currentDrawing else { return }
        
        switch selectedTool {
        case .pen:
            drawing.points.append(value.location)
        case .line, .arrow, .rectangle, .filledRectangle, .circle, .filledCircle:
            drawing.endPoint = value.location
        }

        undoStack.append(elements)
        redoStack.removeAll()
        elements.append(drawing)
        currentDrawing = nil
    }

    // MARK: - History Actions
    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(elements)
        elements = previous
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(elements)
        elements = next
    }

    private func clearAll() {
        guard !elements.isEmpty else { return }
        undoStack.append(elements)
        redoStack.removeAll()
        elements.removeAll()
    }

    private func setupKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) {
                let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
                if chars == "z" {
                    if event.modifierFlags.contains(.shift) {
                        redo()
                        return nil
                    } else {
                        undo()
                        return nil
                    }
                } else if chars == "y" {
                    redo()
                    return nil
                }
            }
            return event
        }
    }

    // MARK: - Export Actions
    private func generateFinalImage() -> NSImage {
        DrawingRenderer.renderCompositeImage(
            baseImage: originalImage,
            elements: elements,
            canvasSize: originalImage.size
        )
    }

    private func copyToClipboard() {
        let finalImage = generateFinalImage()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let tiffData = finalImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            pasteboard.setData(pngData, forType: .png)
            pasteboard.setData(tiffData, forType: .tiff)
        } else {
            pasteboard.writeObjects([finalImage])
        }

        withAnimation {
            copySuccessMessage = "Copied to clipboard!"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onDismiss()
        }
    }

    private func saveToFile() {
        let finalImage = generateFinalImage()
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Save Screenshot"
        savePanel.level = .modalPanel
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        savePanel.nameFieldStringValue = "Screenshot \(formatter.string(from: Date())).png"

        NSApp.activate(ignoringOtherApps: true)

        let targetWindow = EditorWindowManager.shared.windowController?.window ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })

        if let win = targetWindow {
            win.makeKeyAndOrderFront(nil)
            savePanel.beginSheetModal(for: win) { response in
                handleSaveResponse(response, savePanel: savePanel, finalImage: finalImage)
            }
        } else {
            let response = savePanel.runModal()
            handleSaveResponse(response, savePanel: savePanel, finalImage: finalImage)
        }
    }

    private func handleSaveResponse(_ response: NSApplication.ModalResponse, savePanel: NSSavePanel, finalImage: NSImage) {
        guard response == .OK, let url = savePanel.url else { return }
        
        guard let tiffData = finalImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return
        }

        let isJpeg = url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg"
        let fileData = isJpeg 
            ? bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95])
            : bitmap.representation(using: .png, properties: [:])

        if let data = fileData {
            do {
                try data.write(to: url)
                withAnimation {
                    copySuccessMessage = "Saved to file!"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    copySuccessMessage = nil
                }
            } catch {
                NSLog("[QuickCapture] Error saving image: \(error.localizedDescription)")
            }
        }
    }
}
