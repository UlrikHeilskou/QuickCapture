import Cocoa

enum CaptureMode {
    case clipboard
    case annotation
}

final class ScreenCaptureOverlayCoordinator {
    static let shared = ScreenCaptureOverlayCoordinator()

    private var overlayWindows: [SelectionOverlayWindow] = []
    private var keyMonitor: Any?
    private var isSelecting = false
    private var captureMode: CaptureMode = .clipboard

    private(set) var selectionStart: CGPoint?
    private(set) var selectionCurrent: CGPoint?

    private init() {}

    func startSelection(mode: CaptureMode) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard !self.isSelecting else { return }

            self.isSelecting = true
            self.captureMode = mode
            self.selectionStart = nil
            self.selectionCurrent = nil

            self.setupOverlayWindows()
            self.setupKeyMonitor()
            NSCursor.crosshair.push()
        }
    }

    func cancelSelection() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.tearDown()
        }
    }

    func updateSelection(start: CGPoint, current: CGPoint) {
        self.selectionStart = start
        self.selectionCurrent = current
        for window in overlayWindows {
            window.overlayView.needsDisplay = true
        }
    }

    func updateHover() {
        for window in overlayWindows {
            window.overlayView.needsDisplay = true
        }
    }

    func finishSelection(start: CGPoint, end: CGPoint) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let minX = min(start.x, end.x)
            let maxX = max(start.x, end.x)
            let minY = min(start.y, end.y)
            let maxY = max(start.y, end.y)
            let width = maxX - minX
            let height = maxY - minY

            // Require minimal selection size
            guard width >= 5 && height >= 5 else {
                self.tearDown()
                return
            }

            let cocoaRect = CGRect(x: minX, y: minY, width: width, height: height)
            let mode = self.captureMode

            // Close overlays immediately
            self.tearDown()

            // Wait a fraction of a second so WindowServer clears overlay windows from the screen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.executeCapture(cocoaRect: cocoaRect, mode: mode)
            }
        }
    }

    private func executeCapture(cocoaRect: CGRect, mode: CaptureMode) {
        guard let primaryScreen = NSScreen.screens.first else { return }
        let primaryHeight = primaryScreen.frame.height

        // Convert Cocoa screen coordinates (origin bottom-left) to Quartz coordinates (origin top-left)
        let quartzX = Int(round(cocoaRect.origin.x))
        let quartzY = Int(round(primaryHeight - cocoaRect.maxY))
        let quartzW = max(1, Int(round(cocoaRect.width)))
        let quartzH = max(1, Int(round(cocoaRect.height)))
        let rectArg = "-R\(quartzX),\(quartzY),\(quartzW),\(quartzH)"

        switch mode {
        case .clipboard:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-c", "-x", rectArg]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                NSLog("[QuickCapture] Error capturing to clipboard: \(error)")
            }

        case .annotation:
            let tempDir = FileManager.default.temporaryDirectory
            let tempFileURL = tempDir.appendingPathComponent("quickcapture_\(UUID().uuidString).png")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", rectArg, tempFileURL.path]

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                NSLog("[QuickCapture] Error capturing for annotation: \(error)")
                return
            }

            guard FileManager.default.fileExists(atPath: tempFileURL.path),
                  let image = NSImage(contentsOf: tempFileURL) else {
                try? FileManager.default.removeItem(at: tempFileURL)
                return
            }

            DispatchQueue.main.async {
                EditorWindowManager.shared.openEditor(with: image, tempURL: tempFileURL)
            }
        }
    }

    private func setupOverlayWindows() {
        overlayWindows.removeAll()

        for screen in NSScreen.screens {
            let window = SelectionOverlayWindow(screen: screen, coordinator: self)
            overlayWindows.append(window)
            window.orderFrontRegardless()
        }

        NSApp.activate(ignoringOtherApps: true)
        overlayWindows.first?.makeKey()
    }

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.cancelSelection()
                return nil
            }
            return event
        }
    }

    private func tearDown() {
        if let km = keyMonitor {
            NSEvent.removeMonitor(km)
            keyMonitor = nil
        }

        NSCursor.pop()

        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()

        isSelecting = false
        selectionStart = nil
        selectionCurrent = nil
    }
}

final class SelectionOverlayWindow: NSWindow {
    let overlayView: SelectionOverlayView

    init(screen: NSScreen, coordinator: ScreenCaptureOverlayCoordinator) {
        overlayView = SelectionOverlayView(screenFrame: screen.frame, coordinator: coordinator)
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView = overlayView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class SelectionOverlayView: NSView {
    private let screenFrame: NSRect
    private weak var coordinator: ScreenCaptureOverlayCoordinator?
    private var trackingArea: NSTrackingArea?

    init(screenFrame: NSRect, coordinator: ScreenCaptureOverlayCoordinator) {
        self.screenFrame = screenFrame
        self.coordinator = coordinator
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = self.trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .mouseMoved,
            .cursorUpdate,
            .activeAlways,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        guard let coordinator = coordinator else { return }
        let mouseLoc = NSEvent.mouseLocation

        if let start = coordinator.selectionStart {
            // Already anchored, updating selection box
            coordinator.updateSelection(start: start, current: mouseLoc)
        } else {
            // Hovering before first click
            coordinator.updateHover()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.crosshair.set()
        guard let coordinator = coordinator else { return }
        let mouseLoc = NSEvent.mouseLocation

        if let start = coordinator.selectionStart {
            coordinator.updateSelection(start: start, current: mouseLoc)
        } else {
            // Started dragging directly
            coordinator.updateSelection(start: mouseLoc, current: mouseLoc)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let coordinator = coordinator else { return }
        let mouseLoc = NSEvent.mouseLocation

        if let start = coordinator.selectionStart {
            // Second click: finish selection if distance is valid
            let dx = abs(mouseLoc.x - start.x)
            let dy = abs(mouseLoc.y - start.y)
            if dx >= 4 || dy >= 4 {
                coordinator.finishSelection(start: start, end: mouseLoc)
            }
        } else {
            // First click: anchor start corner!
            coordinator.updateSelection(start: mouseLoc, current: mouseLoc)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let coordinator = coordinator else { return }
        let mouseLoc = NSEvent.mouseLocation

        if let start = coordinator.selectionStart {
            let dx = abs(mouseLoc.x - start.x)
            let dy = abs(mouseLoc.y - start.y)
            // If the user performed a click-and-drag gesture (moved >= 5pt while holding mouse button down)
            if dx >= 5 && dy >= 5 {
                coordinator.finishSelection(start: start, end: mouseLoc)
            }
            // If dx, dy < 5, it was a single click to set start point without dragging!
            // We do nothing here, letting the user move the mouse freely until the second click!
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        // Right click cancels selection
        coordinator?.cancelSelection()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            coordinator?.cancelSelection()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Dim the background across this screen
        let dimColor = NSColor(white: 0.0, alpha: 0.30)
        ctx.setFillColor(dimColor.cgColor)
        ctx.fill(bounds)

        guard let coordinator = coordinator else { return }

        if let start = coordinator.selectionStart, let current = coordinator.selectionCurrent {
            // Calculate selection in global Cocoa coordinates
            let minX = min(start.x, current.x)
            let maxX = max(start.x, current.x)
            let minY = min(start.y, current.y)
            let maxY = max(start.y, current.y)
            let globalRect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

            // Convert global Cocoa rect to local view coordinates
            let localRect = NSRect(
                x: globalRect.origin.x - screenFrame.origin.x,
                y: globalRect.origin.y - screenFrame.origin.y,
                width: globalRect.width,
                height: globalRect.height
            )

            let intersected = localRect.intersection(bounds)
            if !intersected.isNull && intersected.width > 0 && intersected.height > 0 {
                // Clear the selection cutout completely so the real screen shows through with 100% clarity
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                ctx.fill(intersected)
                ctx.restoreGState()

                // Draw border around the entire selection rectangle
                ctx.saveGState()
                ctx.setLineWidth(1.5)
                ctx.setStrokeColor(NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0).cgColor) // System Blue
                ctx.stroke(localRect)

                // White subtle inner highlight
                ctx.setLineWidth(0.5)
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
                ctx.stroke(localRect.insetBy(dx: 1, dy: 1))
                ctx.restoreGState()

                // Draw dimension pill badge if the mouse is on this screen
                let mouseLoc = NSEvent.mouseLocation
                if screenFrame.contains(mouseLoc) {
                    drawDimensionBadge(
                        globalWidth: Int(globalRect.width),
                        globalHeight: Int(globalRect.height),
                        near: localRect
                    )
                }
            }
        } else {
            // Waiting for first click: draw helper tooltip near cursor if on this screen
            let mouseLoc = NSEvent.mouseLocation
            if screenFrame.contains(mouseLoc) {
                let localCursor = CGPoint(
                    x: mouseLoc.x - screenFrame.origin.x,
                    y: mouseLoc.y - screenFrame.origin.y
                )
                drawInstructionTooltip(at: localCursor, text: "Click to start selection • Esc to cancel")
            }
        }
    }

    private func drawDimensionBadge(globalWidth: Int, globalHeight: Int, near localRect: NSRect) {
        let text = "\(globalWidth) × \(globalHeight) px  •  Click to finish"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let size = attrString.size()

        let pillPaddingH: CGFloat = 8
        let pillPaddingV: CGFloat = 4
        let pillWidth = size.width + (pillPaddingH * 2)
        let pillHeight = size.height + (pillPaddingV * 2)

        // Position badge below the selection, or above if near bottom of screen
        var badgeY = localRect.minY - pillHeight - 8
        if badgeY < 10 {
            badgeY = localRect.maxY + 8
        }
        var badgeX = localRect.midX - (pillWidth / 2)
        badgeX = max(10, min(badgeX, bounds.width - pillWidth - 10))

        let badgeRect = NSRect(x: badgeX, y: badgeY, width: pillWidth, height: pillHeight)

        let bgPath = NSBezierPath(roundedRect: badgeRect, xRadius: 6, yRadius: 6)
        NSColor(white: 0.1, alpha: 0.85).setFill()
        bgPath.fill()

        NSColor.white.withAlphaComponent(0.2).setStroke()
        bgPath.lineWidth = 0.5
        bgPath.stroke()

        let textPoint = CGPoint(x: badgeRect.minX + pillPaddingH, y: badgeRect.minY + pillPaddingV)
        attrString.draw(at: textPoint)
    }

    private func drawInstructionTooltip(at point: CGPoint, text: String) {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let size = attrString.size()

        let pillPaddingH: CGFloat = 8
        let pillPaddingV: CGFloat = 4
        let pillWidth = size.width + (pillPaddingH * 2)
        let pillHeight = size.height + (pillPaddingV * 2)

        var badgeX = point.x + 15
        if badgeX + pillWidth > bounds.width - 10 {
            badgeX = point.x - pillWidth - 15
        }
        var badgeY = point.y - pillHeight - 15
        if badgeY < 10 {
            badgeY = point.y + 15
        }

        let badgeRect = NSRect(x: badgeX, y: badgeY, width: pillWidth, height: pillHeight)

        let bgPath = NSBezierPath(roundedRect: badgeRect, xRadius: 6, yRadius: 6)
        NSColor(white: 0.1, alpha: 0.85).setFill()
        bgPath.fill()

        NSColor.white.withAlphaComponent(0.25).setStroke()
        bgPath.lineWidth = 0.5
        bgPath.stroke()

        let textPoint = CGPoint(x: badgeRect.minX + pillPaddingH, y: badgeRect.minY + pillPaddingV)
        attrString.draw(at: textPoint)
    }
}
