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
    }

    var segments: [Segment]
    /// What the segments add up to: the goal, or more once you've passed it.
    var total: TimeInterval

    /// Planned segments are capped so a long goal with short sessions stays readable.
    static let maxPlanned = 12

    init(done: [TimeInterval], completed: [Bool], current: (length: TimeInterval, elapsed: TimeInterval)?,
         sessionLength: TimeInterval, goal: TimeInterval) {
        var segments = zip(done, completed).map { Segment(seconds: $0, kind: .done(completed: $1)) }
        var used = done.reduce(0, +)
        if let current {
            segments.append(Segment(seconds: current.length, kind: .current(progress: min(1, current.elapsed / max(1, current.length)))))
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
    var tint: Color = Theme.red
    var height: CGFloat = 4

    private let gap: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let count = plan.segments.count
            let available = max(0, geo.size.width - gap * CGFloat(max(0, count - 1)))
            HStack(spacing: gap) {
                ForEach(plan.segments.indices, id: \.self) { i in
                    let segment = plan.segments[i]
                    segmentView(segment)
                        .frame(width: max(3, available * segment.seconds / max(1, plan.total)))
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func segmentView(_ segment: SessionPlan.Segment) -> some View {
        switch segment.kind {
        case .done(let completed):
            Capsule().fill(Theme.redGradient).opacity(completed ? 1 : 0.55)
        case .current(let progress):
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.22))
                    Capsule().fill(Theme.redGradient)
                        .frame(width: progress > 0 ? max(height, geo.size.width * progress) : 0)
                }
            }
        case .next:
            Capsule().fill(tint.opacity(0.22))
        case .planned:
            Capsule().fill(Theme.track)
        }
    }
}
