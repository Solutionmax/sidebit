import XCTest
@testable import SnipkinCore

final class TransitionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func session(_ activity: Activity, offset: Double = 0, id: String = "one", provider: Provider = .claude) -> Session {
        Session(sessionID: id, provider: provider, cwd: "/work/project", activity: activity, detail: "", updatedAt: now.addingTimeInterval(offset))
    }
    func testStartupSilentAndMetadataPreserved() {
        var tracker = SessionTransitionTracker()
        XCTAssertTrue(tracker.consume([session(.waiting)], now: now).isEmpty)
        let events = tracker.consume([session(.done, offset: 1)], now: now.addingTimeInterval(1))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.provider, .claude)
        XCTAssertEqual(events.first?.project, "project")
        XCTAssertEqual(events.first?.activity, .done)
        XCTAssertEqual(events.first?.date, now.addingTimeInterval(1))
    }
    func testRepeatsAndDisappearanceDoNotReplayButNewCycleDoes() {
        var tracker = SessionTransitionTracker()
        _ = tracker.consume([], now: now)
        let first = tracker.consume([session(.waiting)], now: now)
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(tracker.consume([session(.waiting, offset: 1)], now: now).isEmpty)
        _ = tracker.consume([], now: now)
        XCTAssertTrue(tracker.consume([session(.waiting, offset: 1)], now: now).isEmpty)
        XCTAssertTrue(tracker.consume([session(.working, offset: 2)], now: now).isEmpty)
        let next = tracker.consume([session(.waiting, offset: 3)], now: now)
        XCTAssertEqual(next.count, 1)
        XCTAssertNotEqual(first.first?.id, next.first?.id)
    }
    func testFreshArrivalsOnlyAndFutureRecordsDoNotPoisonState() {
        var tracker = SessionTransitionTracker()
        _ = tracker.consume([], now: now)
        XCTAssertTrue(tracker.consume([session(.done, offset: -31), session(.waiting, offset: 100, id: "future")], now: now).isEmpty)
        XCTAssertEqual(tracker.consume([session(.waiting, id: "future"), session(.done, offset: -30, id: "boundary")], now: now).count, 2)
    }
    func testOlderSnapshotCannotReplayTransition() {
        var tracker = SessionTransitionTracker()
        _ = tracker.consume([session(.working)], now: now)
        XCTAssertEqual(tracker.consume([session(.done, offset: 2)], now: now).count, 1)
        XCTAssertTrue(tracker.consume([session(.working, offset: 1)], now: now).isEmpty)
        XCTAssertTrue(tracker.consume([session(.done, offset: 2)], now: now).isEmpty)
    }
    func testProviderIdentityAndOnlyAttentionOrCompletion() {
        var tracker = SessionTransitionTracker()
        _ = tracker.consume([], now: now)
        let events = tracker.consume([session(.waiting), session(.done, provider: .codex), session(.thinking, id: "thinking"), session(.idle, id: "idle")], now: now)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(Set(events.map(\.id)).count, 2)
    }
    func testEqualTimestampAndEvictedRecordsDoNotReplay() {
        var tracker = SessionTransitionTracker()
        _ = tracker.consume([session(.working)], now: now)
        XCTAssertTrue(tracker.consume([session(.done)], now: now).isEmpty)
        let many = (0..<2100).map { session(.waiting, offset: Double($0) / 1000, id: "session-\($0)") }
        XCTAssertEqual(tracker.consume(many, now: now).count, 2100)
        _ = tracker.consume([], now: now)
        XCTAssertTrue(tracker.consume(many, now: now).isEmpty)
    }

}
