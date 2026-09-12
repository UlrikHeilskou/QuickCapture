# QuickCapture 📸

A lightweight, high-performance native macOS menu bar screenshot & annotation utility.

## ✨ Features

- **⚡ Instant Screenshot to Clipboard (`⌥ + S`)**:
  - Interactive screen selection copied directly to system pasteboard.
- **🎨 Screenshot & Annotation Editor (`⇧ + ⌘ + S`)**:
  - Launches an interactive drawing and annotation editor.
  - **Tools**: Freehand Pen, Directional Arrows, Straight Lines, Rectangles (outlined & filled), Circles/Ellipses (outlined & filled).
  - **Styling**: Color palette + custom color picker, stroke width selector.
  - **History**: Full Undo (`⌘Z`) and Redo (`⇧⌘Z` / `⌘Y`).
  - **Export**: Copy composite image directly to clipboard or save to disk as PNG/JPEG (`⌘S`).
- **🖥️ Native macOS UI**: Floating editor window with automatic size and position memory across sessions.
- **🚀 Launch at Login**: Seamless background menu bar helper.

## 🛠️ Build & Requirements

- macOS 13.0+
- Xcode 15+ / XcodeGen
- Swift 5.0+

```bash
# Generate Xcode project
xcodegen generate

# Build Release
xcodebuild -project QuickCapture.xcodeproj -scheme QuickCapture -configuration Release build
```
