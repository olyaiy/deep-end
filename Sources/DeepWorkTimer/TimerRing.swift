import SwiftUI

/// The dial: 60 tick marks like the Apple Watch timer. Lit ticks show the time
/// left. When `onDrag` is set it shows a knob and reports drags as a fraction (0...1).
struct TimerRing: View {
    /// 0...1 portion of the dial that's lit.
    var fraction: Double
    var tint: Color = Theme.red
    var onDrag: ((Double) -> Void)?
    /// Distance before a drag registers. Keeps a stray click from changing a running timer.
    var dragThreshold: CGFloat = 0

    var body: some View {
        Hoverable { hovered in
            GeometryReader { geo in
                let editable = onDrag != nil
                let size = min(geo.size.width, geo.size.height)
                let radius = size / 2
                let f = max(0, min(1, fraction))

                ZStack {
                    Ticks(major: false, from: f, to: 1)
                        .stroke(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    Ticks(major: true, from: f, to: 1)
                        .stroke(.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    Ticks(major: false, from: 0, to: f)
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    Ticks(major: true, from: 0, to: f)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

                    if editable {
                        let knob: CGFloat = hovered ? 14 : 11
                        Circle()
                            .fill(Theme.knob)
                            .overlay(Circle().stroke(tint, lineWidth: 2))
                            .frame(width: knob, height: knob)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            .offset(y: -(radius - 9))
                            .rotationEffect(.degrees(f * 360))
                    }
                }
                .frame(width: size, height: size)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .contentShape(Circle())
                .pointerStyle(editable ? .grabIdle : nil)
                .gesture(
                    DragGesture(minimumDistance: dragThreshold)
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
}

/// The minor (every minute) or major (every 5) ticks whose positions fall in from..<to.
private struct Ticks: Shape {
    let major: Bool
    var from: Double
    var to: Double

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let start = Int((from * 60).rounded()), end = Int((to * 60).rounded())
        var path = Path()
        guard start < end else { return path }
        for i in start..<end where (i % 5 == 0) == major {
            let a = Double(i) / 60 * 2 * .pi
            let outer = r - 3, inner = r - (major ? 15 : 10)
            path.move(to: CGPoint(x: c.x + outer * sin(a), y: c.y - outer * cos(a)))
            path.addLine(to: CGPoint(x: c.x + inner * sin(a), y: c.y - inner * cos(a)))
        }
        return path
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
