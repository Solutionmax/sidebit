import XCTest
@testable import SnipkinCore

final class UsageCooldownTests: XCTestCase {
    func testRestartKeepsCooldownAndProvidersRemainIndependent() {
        let suite = "SnipkinCooldownTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        UsageCooldown(defaults: defaults).postpone(.claude, by: 1800, now: now)
        let restarted = UsageCooldown(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(restarted.nextRead(for: .claude), now.addingTimeInterval(1800))
        XCTAssertLessThan(restarted.nextRead(for: .codex), now)
        XCTAssertGreaterThan(restarted.nextRead(for: .claude), now.addingTimeInterval(1799))
        XCTAssertLessThanOrEqual(restarted.nextRead(for: .claude), now.addingTimeInterval(1800))
    }

    func testOrdinaryRequestCannotShortenProviderRetryAfter() {
        let suite = "SnipkinCooldownTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cooldown = UsageCooldown(defaults: defaults)
        let now = Date()
        cooldown.postpone(.claude, by: 3600, now: now)
        cooldown.postpone(.claude, now: now.addingTimeInterval(10))
        XCTAssertEqual(cooldown.nextRead(for: .claude), now.addingTimeInterval(3600))
        cooldown.postpone(.codex, by: -10, now: now)
        XCTAssertEqual(cooldown.nextRead(for: .codex), now.addingTimeInterval(300))
    }

    func testAllowanceTintRunsFromGreenToRed() {
        XCTAssertEqual(UsageTint.rgb(0).green, 0.81, accuracy: 0.001)
        XCTAssertEqual(UsageTint.rgb(-5).green, UsageTint.rgb(0).green, "Out of range clamps")
        XCTAssertEqual(UsageTint.rgb(62.5).green, (0.77 + 0.54) / 2, accuracy: 0.001, "Halfway between amber and ember")
        XCTAssertGreaterThan(UsageTint.rgb(95).red, UsageTint.rgb(95).green * 3, "Near the end it is red")
        XCTAssertEqual(UsageTint.rgb(140).red, 0.92, accuracy: 0.001)
    }
}
