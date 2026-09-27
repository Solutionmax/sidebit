import XCTest
@testable import SnipkinCore

final class DesktopActivityTests: XCTestCase {
    func testPresenceAloneIsUnknownAndSendIsIdle() {
        XCTAssertEqual(DesktopActivity.classify(observed: true, stop: false, send: false, approval: false), .unknown)
        XCTAssertEqual(DesktopActivity.classify(observed: true, stop: false, send: true, approval: false), .idle)
    }
    func testWorkingAndApprovalPrecedence() {
        XCTAssertEqual(DesktopActivity.classify(observed: true, stop: true, send: true, approval: false), .working)
        XCTAssertEqual(DesktopActivity.classify(observed: true, stop: true, send: true, approval: true), .waiting)
    }
    func testLostObservationAndReturningComposerNeverCelebrate() {
        XCTAssertEqual(DesktopActivity.classify(observed: true, stop: true, send: false, approval: false), .working)
        XCTAssertEqual(DesktopActivity.classify(observed: false, stop: true, send: true, approval: true), .unknown)
        XCTAssertEqual(DesktopActivity.classify(observed: true, stop: false, send: true, approval: false), .idle)
    }
}

extension DesktopActivityTests {
    func testClaudeEmptyComposerIsIdle() {
        XCTAssertEqual(DesktopActivity.fromControls(labels: ["press and hold to record", "use voice mode"], enabled: ["press and hold to record"], complete: true), .idle)
    }
    func testCoworkStopAndPermissionControlsOverrideComposer() {
        XCTAssertEqual(DesktopActivity.fromControls(labels: ["stop", "press and hold to record"], enabled: ["stop"], complete: true), .working)
        XCTAssertEqual(DesktopActivity.fromControls(labels: ["allow once", "deny", "stop"], enabled: ["allow once", "deny", "stop"], complete: true), .waiting)
    }
    func testPositiveCoworkControlsSurviveAnUnrelatedTruncatedSidebar() {
        XCTAssertEqual(DesktopActivity.fromControls(labels: ["stop task"], enabled: ["stop task"], complete: false), .working)
        XCTAssertEqual(DesktopActivity.fromControls(labels: ["allow once", "deny"], enabled: ["allow once", "deny"], complete: false), .waiting)
    }
    func testDisabledStopAndIncompleteScanDoNotInventActivity() {
        XCTAssertEqual(DesktopActivity.fromControls(labels: ["stop"], enabled: [], complete: true), .unknown)
        XCTAssertEqual(DesktopActivity.fromControls(labels: ["press and hold to record"], enabled: [], complete: false), .unknown)
    }
}
