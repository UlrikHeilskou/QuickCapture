import SwiftUI
import AppKit

enum DrawingTool: String, CaseIterable, Identifiable {
    case pen = "Pen"
    case arrow = "Arrow"
    case line = "Line"
    case rectangle = "Box"
    case filledRectangle = "Box Fill"
    case circle = "Circle"
    case filledCircle = "Circle Fill"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .pen: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "square"
        case .filledRectangle: return "square.fill"
        case .circle: return "circle"
        case .filledCircle: return "circle.fill"
        }
    }

    var label: String {
        switch self {
        case .pen: return "Pen"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Box"
        case .filledRectangle: return "Box Fill"
        case .circle: return "Circle"
        case .filledCircle: return "Circle Fill"
        }
    }
}

struct DrawingElement: Identifiable {
    let id: UUID
    var tool: DrawingTool
    var points: [CGPoint]
    var startPoint: CGPoint
    var endPoint: CGPoint
    var color: Color
    var strokeWidth: CGFloat

    init(
        id: UUID = UUID(),
        tool: DrawingTool,
        points: [CGPoint] = [],
        startPoint: CGPoint = .zero,
        endPoint: CGPoint = .zero,
        color: Color = .red,
        strokeWidth: CGFloat = 4
    ) {
        self.id = id
        self.tool = tool
        self.points = points
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.strokeWidth = strokeWidth
    }

    var boundingBox: CGRect {
        switch tool {
        case .pen:
            guard let first = points.first else { return .zero }
            var minX = first.x
            var maxX = first.x
            var minY = first.y
            var maxY = first.y
            for pt in points {
                minX = min(minX, pt.x)
                maxX = max(maxX, pt.x)
                minY = min(minY, pt.y)
                maxY = max(maxY, pt.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        default:
            let x = min(startPoint.x, endPoint.x)
            let y = min(startPoint.y, endPoint.y)
            let w = abs(endPoint.x - startPoint.x)
            let h = abs(endPoint.y - startPoint.y)
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }
}
