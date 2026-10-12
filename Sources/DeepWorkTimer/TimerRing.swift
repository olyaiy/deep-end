import SwiftUI

/// A thin ring like the Clock app's timer. It shows time remaining (it drains as
/// the session runs). While idle it's a dial: drag around it to set the length.
struct TimerRing: View {
    /// 0...1 portion of the ring that's filled.
    var fraction: Double
    var lineWidth: CGFloat = 7
    /// When set, the ring shows a knob and reports drags as a fraction (0...1).
    var onDrag: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = (size - lineWidth) / 2
            let f = max(0, min(1, fraction))

            ZStack {
                Circle()
                    .stroke(Theme.track, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: f)
                    .stroke(Theme.red, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if onDrag != nil {
                    Circle()
                        .fill(.white)
                        .frame(width: lineWidth + 9, height: lineWidth + 9)
                        .shadow(color: .black.opacity(0.22), radius: 2.5, y: 1)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(f * 360))
                }
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let onDrag else { return }
                        let dx = value.location.x - geo.size.width / 2
                        let dy = value.location.y - geo.size.height / 2
                        // Ignore the middle, where the angle jumps around.
                        guard hypot(dx, dy) > radius * 0.45 else { return }
                        // 0 at 12 o'clock, increasing clockwise.
                        var angle = atan2(dx, -dy)
                        if angle < 0 { angle += 2 * .pi }
                        onDrag(angle / (2 * .pi))
                    },
                including: onDrag == nil ? .subviews : .all
            )
        }
    }
}

/// Template image for the menu bar: a small ring showing time remaining.
enum MenuBarIcon {
    static func ring(remaining: Double, paused: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let inset = rect.insetBy(dx: 1.75, dy: 1.75)
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = inset.width / 2

            let track = NSBezierPath(ovalIn: inset)
            track.lineWidth = 2
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()

            if remaining > 0.001 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                              endAngle: 90 - 360 * min(remaining, 0.999), clockwise: true)
                arc.lineWidth = 2
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }

            if paused {
                NSColor.black.setFill()
                NSBezierPath(roundedRect: NSRect(x: center.x - 2.5, y: center.y - 2.5, width: 1.75, height: 5), xRadius: 0.8, yRadius: 0.8).fill()
                NSBezierPath(roundedRect: NSRect(x: center.x + 0.75, y: center.y - 2.5, width: 1.75, height: 5), xRadius: 0.8, yRadius: 0.8).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
