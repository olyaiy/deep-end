import SwiftUI

/// Today laid out against the daily goal, one segment per session: what you've
/// done (each as long as it actually was), the one running, and what's still
/// needed at your current session length.
struct SessionPlan: Equatable {
    enum Kind: Equatable {
        case done(completed: Bool)
        case current(progress: Double)
        case next
        case planned
    }

    struct Segment: Equatable {
        var seconds: TimeInterval
        var kind: Kind
        /// The session's name, for done and running segments.
        var title = ""
    }

    struct Done {
        var seconds: TimeInterval
        var completed: Bool
        var title: String
    }

    var segments: [Segment]
    /// What the segments add up to: the goal, or more once you've passed it.
    var total: TimeInterval

    /// Planned segments are capped so a long goal with short sessions stays readable.
    static let maxPlanned = 12

    init(done: [Done], current: (length: TimeInterval, elapsed: TimeInterval, title: String)?,
         sessionLength: TimeInterval, goal: TimeInterval) {
        var segments = done.map { Segment(seconds: $0.seconds, kind: .done(completed: $0.completed), title: $0.title) }
        var used = done.reduce(0) { $0 + $1.seconds }
        if let current {
            let progress = min(1, current.elapsed / max(1, current.length))
            segments.append(Segment(seconds: current.length, kind: .current(progress: progress), title: current.title))
            used += current.length
        }

        var remaining = max(0, goal - used)
        // Leftovers under a minute aren't worth a segment.
        if remaining >= 60, sessionLength > 0 {
            var length = sessionLength
            if (remaining / length).rounded(.up) > Double(Self.maxPlanned) { length = remaining / Double(Self.maxPlanned) }
            var first = current == nil
            while remaining >= 60 {
                let piece = min(length, remaining)
                segments.append(Segment(seconds: piece, kind: first ? .next : .planned))
                first = false
                remaining -= piece
            }
        }
        self.segments = segments
        total = max(goal, used)
    }

    var plannedCount: Int { segments.filter { $0.kind == .next || $0.kind == .planned }.count }
    var doneCount: Int { segments.filter { if case .done = $0.kind { true } else { false } }.count }
}

struct SessionBar: View {
    let plan: SessionPlan
    var height: CGFloat = 4

    @StateObject private var hover: HoveredSegment
    private let gap: CGFloat = 3

    /// `hovering` pre-selects a segment (for design previews).
    init(plan: SessionPlan, height: CGFloat = 4, hovering: Int? = nil) {
        self.plan = plan
        self.height = height
        let state = HoveredSegment()
        state.index = hovering
        _hover = StateObject(wrappedValue: state)
    }

    var body: some View {
        GeometryReader { geo in
            let frames = segmentFrames(width: geo.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(plan.segments.indices, id: \.self) { i in
                    segmentView(plan.segments[i])
                        .frame(width: frames[i].width, height: hover.index == i ? height + 2 : height)
                        .offset(x: frames[i].minX, y: hover.index == i ? -1 : 0)
                        // A taller invisible strip makes the thin segments easy to hover.
                        .background(
                            Color.clear
                                .frame(width: frames[i].width + gap, height: 18)
                                .contentShape(Rectangle())
                                .offset(x: frames[i].minX)
                                .onHover { inside in
                                    if inside { hover.index = i } else if hover.index == i { hover.index = nil }
                                }
                        )
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if let i = hover.index, i < plan.segments.count {
                    let text = tooltipText(for: plan.segments[i])
                    let size = tooltipSize(text)
                    // Centred over the segment, kept inside the bar, sitting just above it.
                    let x = min(max(0, frames[i].midX - size.width / 2), max(0, geo.size.width - size.width))
                    tooltip(text)
                        .offset(x: x, y: -size.height - 8)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(Theme.spring, value: hover.index)
        }
        .frame(height: height)
    }

    /// x and width of each segment, proportional to its share of the total.
    private func segmentFrames(width: CGFloat) -> [CGRect] {
        let count = plan.segments.count
        let available = max(0, width - gap * CGFloat(max(0, count - 1)))
        var x: CGFloat = 0
        return plan.segments.map { segment in
            let w = max(3, available * segment.seconds / max(1, plan.total))
            defer { x += w + gap }
            return CGRect(x: x, y: 0, width: w, height: height)
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: SessionPlan.Segment) -> some View {
        // Only finished sessions are red; everything still to come is the same grey.
        switch segment.kind {
        case .done:
            Capsule().fill(Theme.redGradient)
        case .current, .next, .planned:
            Capsule().fill(Theme.track)
        }
    }

    private func tooltipText(for segment: SessionPlan.Segment) -> (title: String, detail: String) {
        let name = segment.title.trimmingCharacters(in: .whitespaces)
        switch segment.kind {
        case .done(let completed):
            return (name.isEmpty ? "Untitled session" : name,
                    DailyStats.durationText(segment.seconds) + (completed ? "" : " · ended early"))
        case .current(let progress):
            return (name.isEmpty ? "This session" : name,
                    "\(DailyStats.durationText(segment.seconds * progress)) of \(DailyStats.durationText(segment.seconds))")
        case .next:
            return ("Up next", DailyStats.durationText(segment.seconds))
        case .planned:
            return ("Still to go", DailyStats.durationText(segment.seconds))
        }
    }

    private static let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let detailFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    /// Measured up front so the label can be placed without a layout pass.
    private func tooltipSize(_ text: (title: String, detail: String)) -> CGSize {
        let title = (text.title as NSString).size(withAttributes: [.font: Self.titleFont])
        let detail = (text.detail as NSString).size(withAttributes: [.font: Self.detailFont])
        return CGSize(width: ceil(title.width + detail.width) + 6 + 16, height: ceil(max(title.height, detail.height)) + 8)
    }

    private func tooltip(_ text: (title: String, detail: String)) -> some View {
        HStack(spacing: 6) {
            Text(text.title).font(Font(Self.titleFont))
            Text(text.detail).font(Font(Self.detailFont)).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
    }
}

final class HoveredSegment: ObservableObject {
    @Published var index: Int?
}
