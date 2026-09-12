import SwiftUI
import AppKit

struct DrawingRenderer {
    static func drawElement(_ element: DrawingElement, in context: inout GraphicsContext) {
        let path = pathFor(element: element)
        let strokeStyle = StrokeStyle(
            lineWidth: element.strokeWidth,
            lineCap: .round,
            lineJoin: .round
        )

        switch element.tool {
        case .filledRectangle:
            let rect = element.boundingBox
            context.fill(Path(rect), with: .color(element.color.opacity(0.45)))
            context.stroke(Path(rect), with: .color(element.color), style: strokeStyle)

        case .filledCircle:
            let rect = element.boundingBox
            context.fill(Path(ellipseIn: rect), with: .color(element.color.opacity(0.45)))
            context.stroke(Path(ellipseIn: rect), with: .color(element.color), style: strokeStyle)

        case .arrow:
            context.stroke(path, with: .color(element.color), style: strokeStyle)
            let arrowHeadPath = pathForArrowHead(start: element.startPoint, end: element.endPoint, strokeWidth: element.strokeWidth)
            context.fill(arrowHeadPath, with: .color(element.color))
            context.stroke(arrowHeadPath, with: .color(element.color), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))

        default:
            context.stroke(path, with: .color(element.color), style: strokeStyle)
        }
    }

    static func pathFor(element: DrawingElement) -> Path {
        var path = Path()
        switch element.tool {
        case .pen:
            guard let first = element.points.first else { return path }
            path.move(to: first)
            for pt in element.points.dropFirst() {
                path.addLine(to: pt)
            }

        case .line:
            path.move(to: element.startPoint)
            path.addLine(to: element.endPoint)

        case .arrow:
            path.move(to: element.startPoint)
            path.addLine(to: element.endPoint)

        case .rectangle, .filledRectangle:
            path.addRect(element.boundingBox)

        case .circle, .filledCircle:
            path.addEllipse(in: element.boundingBox)
        }
        return path
    }

    static func pathForArrowHead(start: CGPoint, end: CGPoint, strokeWidth: CGFloat) -> Path {
        var path = Path()
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance > 3 else { return path }

        let angle = atan2(dy, dx)
        let headLength = max(14.0, strokeWidth * 3.8)
        let headAngle: CGFloat = .pi / 6.0 // 30 degrees

        let p1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        path.move(to: end)
        path.addLine(to: p1)
        path.addLine(to: p2)
        path.closeSubpath()
        return path
    }

    static func renderCompositeImage(baseImage: NSImage, elements: [DrawingElement], canvasSize: CGSize) -> NSImage {
        let imageSize = baseImage.size
        guard imageSize.width > 0, imageSize.height > 0, canvasSize.width > 0, canvasSize.height > 0 else {
            return baseImage
        }

        let scaleX = imageSize.width / canvasSize.width
        let scaleY = imageSize.height / canvasSize.height

        let targetImage = NSImage(size: imageSize)
        targetImage.lockFocus()

        guard let nsContext = NSGraphicsContext.current else {
            targetImage.unlockFocus()
            return baseImage
        }
        let cgContext = nsContext.cgContext

        // Draw original base image
        baseImage.draw(in: CGRect(origin: .zero, size: imageSize))

        // Save state for scaling to image coordinate space
        cgContext.saveGState()
        
        // AppKit lockFocus coordinate system origin is bottom-left, flip Y to match SwiftUI top-left origin
        cgContext.translateBy(x: 0, y: imageSize.height)
        cgContext.scaleBy(x: scaleX, y: -scaleY)

        for element in elements {
            drawCGElement(element, in: cgContext)
        }

        cgContext.restoreGState()
        targetImage.unlockFocus()

        return targetImage
    }

    private static func drawCGElement(_ element: DrawingElement, in ctx: CGContext) {
        let nsColor = NSColor(element.color)
        ctx.setStrokeColor(nsColor.cgColor)
        ctx.setLineWidth(element.strokeWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch element.tool {
        case .pen:
            guard let first = element.points.first else { return }
            ctx.beginPath()
            ctx.move(to: first)
            for pt in element.points.dropFirst() {
                ctx.addLine(to: pt)
            }
            ctx.strokePath()

        case .line:
            ctx.beginPath()
            ctx.move(to: element.startPoint)
            ctx.addLine(to: element.endPoint)
            ctx.strokePath()

        case .arrow:
            ctx.beginPath()
            ctx.move(to: element.startPoint)
            ctx.addLine(to: element.endPoint)
            ctx.strokePath()

            let dx = element.endPoint.x - element.startPoint.x
            let dy = element.endPoint.y - element.startPoint.y
            let distance = hypot(dx, dy)
            if distance > 3 {
                let angle = atan2(dy, dx)
                let headLength = max(14.0, element.strokeWidth * 3.8)
                let headAngle: CGFloat = .pi / 6.0

                let p1 = CGPoint(
                    x: element.endPoint.x - headLength * cos(angle - headAngle),
                    y: element.endPoint.y - headLength * sin(angle - headAngle)
                )
                let p2 = CGPoint(
                    x: element.endPoint.x - headLength * cos(angle + headAngle),
                    y: element.endPoint.y - headLength * sin(angle + headAngle)
                )

                ctx.beginPath()
                ctx.move(to: element.endPoint)
                ctx.addLine(to: p1)
                ctx.addLine(to: p2)
                ctx.closePath()
                ctx.setFillColor(nsColor.cgColor)
                ctx.fillPath()
            }

        case .rectangle:
            ctx.stroke(element.boundingBox)

        case .filledRectangle:
            let fillColor = nsColor.withAlphaComponent(0.45)
            ctx.setFillColor(fillColor.cgColor)
            ctx.fill(element.boundingBox)
            ctx.stroke(element.boundingBox)

        case .circle:
            ctx.strokeEllipse(in: element.boundingBox)

        case .filledCircle:
            let fillColor = nsColor.withAlphaComponent(0.45)
            ctx.setFillColor(fillColor.cgColor)
            ctx.fillEllipse(in: element.boundingBox)
            ctx.strokeEllipse(in: element.boundingBox)
        }
    }
}
