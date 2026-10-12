import SwiftUI

/// The timer ring. It shows time remaining (it drains as the session runs).
/// While idle it's a dial: drag around it to set the length.
struct TimerRing: View {
    /// 0...1 portion of the ring that's filled.
    var fraction: Double
    /// When set, the ring shows a knob and reports drags as a fraction (0...1).
    var onDrag: ((Double) -> Void)?

    var body: some View {
        Hoverable { hovered in
            GeometryReader { geo in
                let editable = onDrag != nil
                let lineWidth: CGFloat = editable && hovered ? 9 : 7
                let size = min(geo.size.width, geo.size.height)
                let radius = (size - 9) / 2
                let f = max(0, min(1, fraction))

                ZStack {
                    // Soft red glow behind everything, for warmth and for the glass to pick up.
                    Circle()
                        .fill(Theme.red.opacity(0.10))
                        .blur(radius: 28)
                        .scaleEffect(0.95)

                    Circle()
                        .stroke(Theme.track, lineWidth: lineWidth)
                        .frame(width: radius * 2, height: radius * 2)

                    arc(f)
                        .stroke(Theme.red, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .blur(radius: 6)
                        .opacity(0.35)
                        .frame(width: radius * 2, height: radius * 2)

                    arc(f)
                        .stroke(Theme.redGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .frame(width: radius * 2, height: radius * 2)

                    if editable {
                        let knob: CGFloat = hovered ? 20 : 15
                        Circle()
                            .fill(.white)
                            .frame(width: knob, height: knob)
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                            .overlay(Circle().fill(Theme.red).frame(width: hovered ? 6 : 0, height: hovered ? 6 : 0))
                            .offset(y: -radius)
                            .rotationEffect(.degrees(f * 360))
                    }
                }
                .frame(width: size, height: size)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .contentShape(Circle())
                .pointerStyle(editable ? .grabIdle : nil)
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
                    including: editable ? .all : .subviews
                )
            }
        }
    }

    private func arc(_ f: Double) -> some Shape {
        Circle().trim(from: 0, to: f).rotation(.degrees(-90))
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
