import SwiftUI

/// The big ring. While running it shows progress; while idle it's a dial you
/// drag around to set the session length (one full turn = `Prefs.maxWorkMinutes`).
struct Dial: View {
    var progress: Double
    var phase: Phase
    var lineWidth: CGFloat = 12
    var ticks = 24
    /// When set, dragging on the ring reports a new fraction (0...1).
    var onDrag: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = (size - lineWidth) / 2
            let p = max(0.0001, min(1, progress))

            ZStack {
                // Track
                Circle()
                    .stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)

                // Tick marks inside the ring
                ForEach(0..<ticks, id: \.self) { i in
                    let major = i % (ticks / 4) == 0
                    Capsule()
                        .fill(Color.primary.opacity(major ? 0.28 : 0.13))
                        .frame(width: major ? 2 : 1.5, height: major ? 7 : 4)
                        .offset(y: -(radius - lineWidth / 2 - 9))
                        .rotationEffect(.degrees(Double(i) / Double(ticks) * 360))
                }

                // Glow
                arc(p)
                    .stroke(phase.gradientAngular(p), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .blur(radius: 9)
                    .opacity(0.55)

                // Progress arc
                arc(p)
                    .stroke(phase.gradientAngular(p), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                // Knob at the end of the arc
                Circle()
                    .fill(.white)
                    .frame(width: lineWidth - 3, height: lineWidth - 3)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(p * 360))
                    .opacity(progress > 0.001 ? 1 : 0)
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
                        guard hypot(dx, dy) > radius * 0.4 else { return }
                        // 0 at 12 o'clock, increasing clockwise.
                        var angle = atan2(dx, -dy)
                        if angle < 0 { angle += 2 * .pi }
                        onDrag(angle / (2 * .pi))
                    },
                including: onDrag == nil ? .subviews : .all
            )
        }
    }

    private func arc(_ p: Double) -> some Shape {
        Circle()
            .trim(from: 0, to: p)
            .rotation(.degrees(-90))
    }
}

extension Phase {
    /// A gradient that runs along the arc from 12 o'clock to the arc's end.
    func gradientAngular(_ progress: Double) -> AngularGradient {
        AngularGradient(
            colors: [colors[1], colors[0]],
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * max(progress, 0.05))
        )
    }
}

/// Dots showing where you are in the cycle before a long break.
struct CycleDots: View {
    var total: Int
    var completed: Int
    var current: Int?
    var phase: Phase

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(fill(for: i))
                    .frame(width: i == current ? 16 : 6, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: current)
            }
        }
    }

    private func fill(for i: Int) -> AnyShapeStyle {
        if i < completed { return AnyShapeStyle(Phase.work.gradient) }
        if i == current { return AnyShapeStyle(phase.gradient) }
        return AnyShapeStyle(Color.primary.opacity(0.15))
    }
}

/// Template image for the menu bar: a small progress ring.
enum MenuBarIcon {
    static func ring(progress: Double, paused: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let inset = rect.insetBy(dx: 1.75, dy: 1.75)
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = inset.width / 2

            let track = NSBezierPath(ovalIn: inset)
            track.lineWidth = 2
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()

            if progress > 0.001 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                              endAngle: 90 - 360 * min(progress, 0.999), clockwise: true)
                arc.lineWidth = 2
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }

            NSColor.black.setFill()
            if paused {
                NSBezierPath(roundedRect: NSRect(x: center.x - 2.5, y: center.y - 2.5, width: 1.75, height: 5), xRadius: 0.8, yRadius: 0.8).fill()
                NSBezierPath(roundedRect: NSRect(x: center.x + 0.75, y: center.y - 2.5, width: 1.75, height: 5), xRadius: 0.8, yRadius: 0.8).fill()
            } else {
                NSBezierPath(ovalIn: NSRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
