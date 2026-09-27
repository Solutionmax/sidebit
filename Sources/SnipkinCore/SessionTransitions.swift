import Foundation

public struct SessionTransition: Identifiable, Equatable, Sendable {
    public let id: String
    public let provider: Provider
    public let project: String
    public let activity: Activity
    public let date: Date
}

public struct SessionTransitionTracker {
    private struct Observation {
        let activity: Activity
        let date: Date
    }
    private var observations: [String: Observation] = [:]
    private var seeded = false
    // At capacity, suppress older arrivals rather than replay evicted records.
    private var evictedThrough = Date.distantPast
    private let capacity = 2048

    public init() {}

    public mutating func consume(_ sessions: [Session], now: Date = Date()) -> [SessionTransition] {
        var events: [SessionTransition] = []
        for session in sessions.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            let age = now.timeIntervalSince(session.updatedAt)
            // Allow small clock skew, but do not let bad future dates poison tracking.
            guard age.isFinite, age >= -5 else { continue }
            let previous = observations[session.id]
            if let previous, session.updatedAt <= previous.date { continue }
            guard previous != nil || session.updatedAt > evictedThrough else { continue }
            observations[session.id] = Observation(activity: session.activity, date: session.updatedAt)
            if seeded, age <= 30, previous?.activity != session.activity,
               session.activity == .waiting || session.activity == .done {
                events.append(SessionTransition(
                    id: "\(session.id):\(session.activity.rawValue):\(session.updatedAt.timeIntervalSince1970)",
                    provider: session.provider, project: session.project,
                    activity: session.activity, date: session.updatedAt
                ))
            }
        }
        seeded = true
        if observations.count > capacity {
            let oldest = observations.sorted { $0.value.date < $1.value.date }
                .prefix(observations.count - capacity)
            for (id, observation) in oldest {
                evictedThrough = max(evictedThrough, observation.date)
                observations.removeValue(forKey: id)
            }
        }
        return events
    }
}
