import XCTest
@testable import SnipkinCore
final class UsageTests: XCTestCase {
    func testClaudeWindowsAndFractionalDate() throws {
        let s = try UsageReader.parseClaude(Data(#"{"five_hour":{"utilization":0,"resets_at":"2026-09-27T03:19:59.976161+00:00"},"seven_day":{"utilization":96,"resets_at":null}}"#.utf8))
        XCTAssertEqual(s.windows.map(\.usedPercent), [0,96])
        XCTAssertEqual(s.windows.map(\.durationMinutes), [300,10080])
        XCTAssertNotNil(s.windows[0].resetsAt)
        XCTAssertNil(s.windows[1].resetsAt)
    }
    func testCodexPrimaryCanBeWeeklyAndSecondaryAbsent() throws {
        let s = try UsageReader.parseCodex(Data(#"{"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":6,"limit_window_seconds":604800,"reset_at":1791063876},"secondary_window":null}}"#.utf8))
        XCTAssertEqual(s.windows.count,1)
        XCTAssertEqual(s.windows[0].title,"7 days")
        XCTAssertEqual(s.windows[0].usedPercent,6)
        XCTAssertEqual(s.plan,"prolite")
    }
    func testMalformedNeverBecomesZero() {
        for json in ["{}", #"{"five_hour":{"utilization":101}}"#, #"{"five_hour":{"utilization":true}}"#, #"{"five_hour":{"utilization":1,"resets_at":"oops"}}"#] {
            XCTAssertThrowsError(try UsageReader.parseClaude(Data(json.utf8)))
        }
        XCTAssertThrowsError(try UsageReader.parseCodex(Data(#"{"rate_limit":{"primary_window":{"used_percent":8}}}"#.utf8)))
    }
    func testHTTPClassificationAndBackoff() {
        XCTAssertThrowsError(try UsageReader.checkStatus(401,retryAfter:nil)) { error in
            guard case UsageFailure.notSignedIn = error else { return XCTFail("Expected sign in") }
        }
        XCTAssertThrowsError(try UsageReader.checkStatus(429,retryAfter:"0")) { error in
            guard case UsageFailure.rateLimited(let delay) = error else { return XCTFail("Expected backoff") }
            XCTAssertGreaterThanOrEqual(delay,60)
        }
        XCTAssertNoThrow(try UsageReader.checkStatus(200,retryAfter:nil))
    }
    func testAlternateDurationsAndTwoWindows() throws {
        let s = try UsageReader.parseCodex(Data(#"{"rate_limit":{"primary_window":{"used_percent":100,"limit_window_seconds":18000},"secondary_window":{"used_percent":12.5,"limit_window_seconds":5400}}}"#.utf8))
        XCTAssertEqual(s.windows.map(\.title), ["5 hours", "90 minutes"])
        XCTAssertEqual(s.windows.map(\.usedPercent), [100, 12.5])
        XCTAssertNil(s.windows[0].resetsAt)
    }
    func testRetryAfterDateAndServiceFailure() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertThrowsError(try UsageReader.checkStatus(503, retryAfter: "Thu, 01 Jan 1970 00:10:00 GMT", now: now)) { error in
            guard case UsageFailure.rateLimited(let delay) = error else { return XCTFail("Expected backoff") }
            XCTAssertEqual(delay, 600)
        }
        XCTAssertThrowsError(try UsageReader.checkStatus(500, retryAfter: nil)) { error in
            guard case UsageFailure.unavailable = error else { return XCTFail("Expected unavailable") }
        }
        XCTAssertThrowsError(try UsageReader.checkStatus(302, retryAfter: nil))
    }
    func testMissingCredentialsGivesSafeSignInError() async {
        do {
            _ = try await UsageReader(home: URL(fileURLWithPath: "/nonexistent-snipkin-test-home")).fetch(.codex)
            XCTFail("Expected missing credentials")
        } catch {
            guard case UsageFailure.notSignedIn = error else { return XCTFail("Expected safe sign in error") }
            XCTAssertFalse(error.localizedDescription.contains("/nonexistent"))
        }
    }
}
