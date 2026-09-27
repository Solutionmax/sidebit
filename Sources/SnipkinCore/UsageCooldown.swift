import Foundation

/// Persists request spacing separately for each provider, including Retry-After.
public struct UsageCooldown {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func nextRead(for provider: Provider) -> Date {
        defaults.object(forKey: "usageNextRead.\(provider.rawValue)") as? Date ?? .distantPast
    }

    public func postpone(_ provider: Provider, by delay: TimeInterval = 300, now: Date = Date()) {
        let safeDelay = delay.isFinite ? max(300, delay) : 300
        let deadline = max(nextRead(for: provider), now.addingTimeInterval(safeDelay))
        defaults.set(deadline, forKey: "usageNextRead.\(provider.rawValue)")
    }

    public func reset(_ provider: Provider) { defaults.removeObject(forKey: "usageNextRead.\(provider.rawValue)") }
}
