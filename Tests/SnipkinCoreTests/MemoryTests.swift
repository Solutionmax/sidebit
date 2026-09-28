import XCTest
@testable import SnipkinCore

final class MemoryTests: XCTestCase {
    func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func date(_ day: Int, _ hour: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))! }

    func testJournalCountsEventsAndUnlocksMomentsOnce() throws {
        let journal = Journal(directory: try temporary()), now = date(23, 2) // Wednesday, 02:00
        XCTAssertEqual(try journal.record(event: "Stop", tool: nil, provider: .claude, project: "api", now: now, calendar: calendar), [.firstTurn, .nightOwl])
        XCTAssertEqual(try journal.record(event: "Stop", tool: nil, provider: .claude, project: "api", now: now, calendar: calendar), [])
        for tool in ["Bash", "exec_command", "apply_patch", "Read", "custom"] {
            try journal.record(event: "PreToolUse", tool: tool, provider: .codex, project: "web", now: now, calendar: calendar)
        }
        try journal.record(event: "MadeUp", tool: nil, provider: .codex, project: "ignored", now: now, calendar: calendar)
        let day = journal.day(now)
        XCTAssertEqual(journal.day(now).day, "2026-09-23")
        XCTAssertEqual([day.turns, day.tools, day.commands, day.edits, day.reads], [2, 5, 2, 1, 1])
        XCTAssertEqual(day.projects, ["api", "web"])
        XCTAssertTrue(journal.moments().contains { $0.id == Moment.tagTeam.rawValue && !$0.seen })
        try journal.markSeen()
        XCTAssertTrue(journal.moments().allSatisfy(\.seen))
    }

    func testStreakAndLines() throws {
        let journal = Journal(directory: try temporary())
        for day in 20...22 { try journal.record(event: "Stop", tool: nil, provider: .claude, project: "p", now: date(day, 12), calendar: calendar) }
        XCTAssertEqual(journal.streak(endingOn: date(22, 13), calendar: calendar), 3)
        XCTAssertTrue(journal.moments().contains { $0.id == Moment.streak3.rawValue })
        XCTAssertEqual(journal.streak(endingOn: date(24, 13), calendar: calendar), 0)
        try journal.recordLines(session: "a", added: 600, removed: 10, project: "p", now: date(22, 14), calendar: calendar)
        try journal.recordLines(session: "a", added: 700, removed: 20, project: "p", now: date(22, 15), calendar: calendar)
        let unlocked = try journal.recordLines(session: "b", added: 400, removed: 0, project: "p", now: date(22, 16), calendar: calendar)
        XCTAssertEqual(unlocked, [.thousandLines])
        XCTAssertEqual(journal.day(date(22, 16)).linesAdded, 1100)
        XCTAssertEqual(journal.day(date(22, 16)).linesRemoved, 20)
    }

    func testMomentRules() {
        var day = DayJournal(day: "x")
        day.linesRemoved(600)
        XCTAssertTrue(Moment.earned(by: day, streak: 0).contains(.marieKondo))
        XCTAssertFalse(Moment.earned(by: DayJournal(day: "x"), streak: 0).contains(.firstTurn))
        XCTAssertTrue(Moment.earned(by: DayJournal(day: "x"), streak: 7).contains(.streak7))
        XCTAssertTrue(Moment.allCases.allSatisfy { $0.title.count <= 20 && !$0.blurb.isEmpty })
    }

    func testStatusLineParsesRateLimitsAndRendersBit() throws {
        let json = #"{"session_id":"s1","workspace":{"project_dir":"/Users/me/app"},"cost":{"total_lines_added":12,"total_lines_removed":3},"context_window":{"used_percentage":8},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600},"spend_limit":{"used_percentage":150}}}"#
        let input = try XCTUnwrap(StatusLine.parse(Data(json.utf8)))
        XCTAssertEqual(input.project, "app")
        XCTAssertEqual(input.usage?.windows.map(\.usedPercent), [23.5, 41.2])
        XCTAssertEqual(input.usage?.windows.first?.resetsAt, Date(timeIntervalSince1970: 1738425600))
        XCTAssertEqual([input.linesAdded, input.linesRemoved], [12, 3])
        let line = StatusLine.render(activity: .working, detail: "Running command", input: input, showUsage: true)
        XCTAssertTrue(line.contains("Bit") && line.contains("5h 24%") && line.contains("7d 41%"))
        XCTAssertNil(StatusLine.parse(Data("nope".utf8)))
        XCTAssertNil(StatusLine.parse(Data(#"{"rate_limits":{"five_hour":{"used_percentage":"x"}}}"#.utf8))?.usage)
    }

    func testStatusLineRunStoresUsageAndWrapsOriginal() throws {
        let root = try temporary()
        let config = StatusLineConfig(original: #"{"type":"command","command":"cat >/dev/null; echo mine"}"#)
        let usage = UsageStore(directory: root.appendingPathComponent("usage"))
        let output = StatusLine.run(input: Data(#"{"session_id":"s","rate_limits":{"five_hour":{"used_percentage":5}}}"#.utf8), config: config,
                                    sessions: SessionFiles(directory: root), journal: Journal(directory: root.appendingPathComponent("journal")), usage: usage)
        XCTAssertTrue(output.hasPrefix("mine\n"))
        XCTAssertFalse(output.contains("5h"), "The wrapped line already owns the details")
        XCTAssertEqual(usage.load(.claude)?.windows.first?.usedPercent, 5)
        XCTAssertEqual(StatusLine.run(input: Data(), config: StatusLineConfig(showBit: false), sessions: SessionFiles(directory: root), usage: usage), "")
    }

    func testStatusLineNeverOverwritesFresherLimitsWithStaleOnes() throws {
        let root = try temporary()
        let usage = UsageStore(directory: root.appendingPathComponent("usage"))
        let sessions = SessionFiles(directory: root), journal = Journal(directory: root.appendingPathComponent("journal"))
        let reset = Date(timeIntervalSince1970: 1_900_000_000)
        func line(_ five: Double, resets: Date = reset) -> Data {
            Data(#"{"session_id":"idle","rate_limits":{"five_hour":{"used_percentage":\#(five),"resets_at":\#(Int(resets.timeIntervalSince1970))}}}"#.utf8)
        }
        // The account API says 40%; an idle session still remembers 21% from this morning.
        try usage.save(UsageSnapshot(provider: .claude, windows: [UsageWindow(id: "five_hour", title: "5 hours", usedPercent: 40, resetsAt: reset, durationMinutes: 300)],
                                     fetchedAt: reset.addingTimeInterval(-3600), source: "Claude account usage"))
        _ = StatusLine.run(input: line(21), sessions: sessions, journal: journal, usage: usage, now: reset.addingTimeInterval(-3000))
        XCTAssertEqual(usage.load(.claude)?.windows.first?.usedPercent, 40, "A lower reading in the same window is stale")
        // A higher reading is newer news.
        _ = StatusLine.run(input: line(45), sessions: sessions, journal: journal, usage: usage, now: reset.addingTimeInterval(-2900))
        XCTAssertEqual(usage.load(.claude)?.windows.first?.usedPercent, 45)
        // Repeating the same reading must not look fresh, or Bit never asks the account again.
        _ = StatusLine.run(input: line(45), sessions: sessions, journal: journal, usage: usage, now: reset.addingTimeInterval(-2000))
        XCTAssertEqual(usage.load(.claude)?.fetchedAt, reset.addingTimeInterval(-2900))
        // A new window starts low again, and that counts.
        _ = StatusLine.run(input: line(3, resets: reset.addingTimeInterval(18_000)), sessions: sessions, journal: journal, usage: usage, now: reset.addingTimeInterval(60))
        XCTAssertEqual(usage.load(.claude)?.windows.first?.usedPercent, 3)
        // Without reset times, only a rise counts.
        func bare(_ value: Double) -> UsageSnapshot {
            UsageSnapshot(provider: .claude, windows: [UsageWindow(id: "five_hour", title: "5 hours", usedPercent: value, resetsAt: nil, durationMinutes: 300)], source: "Claude Code status line")
        }
        XCTAssertFalse(bare(10).adds(to: bare(40)))
        XCTAssertFalse(bare(40).adds(to: bare(40)))
        XCTAssertTrue(bare(41).adds(to: bare(40)))
    }

    func testStatusLineInstallKeepsAndRestoresExistingLine() throws {
        let home = try temporary(), state = try temporary()
        let folder = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let settings = folder.appendingPathComponent("settings.json")
        try Data(#"{"theme":"dark","statusLine":{"type":"command","command":"npx ccstatusline","padding":1}}"#.utf8).write(to: settings)
        let installer = HookInstaller(home: home, executable: URL(fileURLWithPath: "/Applications/Sidebit.app/Contents/MacOS/Sidebit"))
        try installer.installStatusLine(state: state)
        try installer.installStatusLine(state: state)
        XCTAssertTrue(installer.isStatusLineInstalled())
        XCTAssertEqual(StatusLineConfig.load(state).wrappedCommand, "npx ccstatusline")
        let installed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        XCTAssertEqual((installed["statusLine"] as? [String: Any])?["padding"] as? Int, 1)
        try installer.uninstallStatusLine(state: state)
        let restored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        XCTAssertEqual((restored["statusLine"] as? [String: Any])?["command"] as? String, "npx ccstatusline")
        XCTAssertEqual(restored["theme"] as? String, "dark")
        XCTAssertFalse(installer.isStatusLineInstalled())

        // Another tool took over: uninstalling must not touch it or forget the saved original.
        try installer.installStatusLine(state: state)
        try Data(#"{"statusLine":{"type":"command","command":"other-tool"}}"#.utf8).write(to: settings)
        try installer.uninstallStatusLine(state: state)
        XCTAssertEqual(StatusLineConfig.load(state).wrappedCommand, "npx ccstatusline")
        XCTAssertTrue(try String(contentsOf: settings).contains("other-tool"))

        try Data("{}".utf8).write(to: settings)
        var cleared = StatusLineConfig.load(state); cleared.original = nil; try cleared.save(state)
        try installer.installStatusLine(state: state)
        try installer.uninstallStatusLine(state: state)
        XCTAssertNil(try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])["statusLine"])
    }

    func testHungWrappedStatusLineIsKilledAsAGroup() {
        let started = Date()
        XCTAssertNil(StatusLine.runWrapped("sleep 30 | cat", input: Data(), timeout: 0.5))
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertEqual(StatusLine.runWrapped("tr a b", input: Data("aaa".utf8)), "bbb")
    }

    func testQuipsAreStableAndContextual() {
        let context = Quips.Context(activity: .working, detail: "Running command", hour: 2, bothAgentsBusy: true)
        XCTAssertEqual(Quips.line(context, seed: 42), Quips.line(context, seed: 42))
        XCTAssertTrue(Quips.candidates(context).contains("sudo make me a sandwich."))
        XCTAssertTrue(Quips.candidates(context).contains("Two agents, one tiny me."))
        XCTAssertTrue(Quips.candidates(context).contains("It's late. The bugs are nocturnal too."))
        XCTAssertEqual(Quips.candidates(.init(activity: .thinking, detail: "Recovering from an error")).first, "That didn't work. Plan B!")
        for activity in Activity.allCases { XCTAssertFalse(Quips.line(.init(activity: activity), seed: -7).isEmpty) }
        XCTAssertTrue((Quips.base.values.flatMap { $0 } + Quips.byDetail.values.flatMap { $0 }).allSatisfy { $0.count <= 44 })
    }

    func testUsageStoreKeepsNewest() throws {
        let store = UsageStore(directory: try temporary()), now = Date()
        let window = UsageWindow(id: "five_hour", title: "5 hours", usedPercent: 10, resetsAt: nil, durationMinutes: 300)
        try store.save(UsageSnapshot(provider: .claude, windows: [window], fetchedAt: now, source: "new"))
        try store.save(UsageSnapshot(provider: .claude, windows: [window], fetchedAt: now.addingTimeInterval(-60), source: "old"))
        XCTAssertEqual(store.load(.claude)?.source, "new")
        XCTAssertNil(store.load(.codex))
    }

    func testHookRecordsJournalWithoutContent() throws {
        let root = try temporary(), journal = Journal(directory: root)
        let data = try JSONSerialization.data(withJSONObject: ["hook_event_name": "PreToolUse", "tool_name": "Bash", "cwd": "/x/secret-project", "tool_input": ["command": "TOP SECRET"]])
        HookRuntime.recordJournal(data, provider: .claude, journal: journal)
        XCTAssertEqual(journal.day().commands, 1)
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            XCTAssertFalse(try String(contentsOf: file).contains("TOP SECRET"))
        }
    }
}

private extension DayJournal {
    mutating func linesRemoved(_ count: Int) { sessionLines["t"] = [0, count] }
}

final class PolishTests: XCTestCase {
    func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func credentials(_ expiry: Date) -> Data {
        try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": ["accessToken": "tok-\(Int(expiry.timeIntervalSince1970))", "expiresAt": expiry.timeIntervalSince1970 * 1000]])
    }

    func testExpiredFileFallsBackToKeychainOnlyWhenAllowed() throws {
        let home = try temporary(), now = Date()
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try credentials(now.addingTimeInterval(-3600)).write(to: home.appendingPathComponent(".claude/.credentials.json"))
        let fresh = credentials(now.addingTimeInterval(3600))
        KeychainTokenCache.shared.clear()
        XCTAssertThrowsError(try UsageReader(home: home, keychain: { _ in fresh }).credentials(.claude, now: now)) { error in
            guard case UsageFailure.needsKeychain = error else { return XCTFail("\(error)") }
        }
        let token = try UsageReader(home: home, allowKeychain: true, keychain: { $0 == UsageReader.claudeKeychainService ? fresh : nil }).credentials(.claude, now: now).token
        XCTAssertEqual(token, "tok-\(Int(now.addingTimeInterval(3600).timeIntervalSince1970))")
        KeychainTokenCache.shared.clear()
        XCTAssertThrowsError(try UsageReader(home: home, allowKeychain: true, keychain: { _ in nil }).credentials(.claude, now: now))
        // Once read, the token is reused from memory without touching the Keychain again.
        _ = try UsageReader(home: home, allowKeychain: true, keychain: { _ in fresh }).credentials(.claude, now: now)
        var reads = 0
        _ = try UsageReader(home: home, allowKeychain: true, keychain: { _ in reads += 1; return nil }).credentials(.claude, now: now)
        XCTAssertEqual(reads, 0)
        KeychainTokenCache.shared.clear()
        try credentials(now.addingTimeInterval(7200)).write(to: home.appendingPathComponent(".claude/.credentials.json"))
        var asked = false
        _ = try UsageReader(home: home, allowKeychain: true, keychain: { _ in asked = true; return nil }).credentials(.claude, now: now)
        XCTAssertFalse(asked, "A valid file never touches the Keychain")
    }

    func testOldJournalFilesDecodeAndHoursCount() throws {
        let old = #"{"day":"2026-09-27","turns":3,"projects":["a"],"sessionLines":{}}"#
        let day = try JSONDecoder.journal.decode(DayJournal.self, from: Data(old.utf8))
        XCTAssertEqual(day.turns, 3); XCTAssertEqual(day.hours.count, 24); XCTAssertNil(day.busiestHour)
        let journal = Journal(directory: try temporary())
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        let ten = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 10))!
        for _ in 0..<3 { try journal.record(event: "Stop", tool: nil, provider: .claude, project: "p", now: ten, calendar: calendar) }
        try journal.record(event: "Stop", tool: nil, provider: .codex, project: "p", now: ten.addingTimeInterval(16 * 3600), calendar: calendar)
        XCTAssertEqual(journal.day(ten).busiestHour, 10)
        let week = WeekSummary(days: journal.week(endingOn: ten.addingTimeInterval(86400), calendar: calendar))
        XCTAssertEqual(week.days.count, 7); XCTAssertEqual(week.turns, 4); XCTAssertEqual(week.latestHour, 2)
        XCTAssertEqual(week.claudeShare, 0.75)
    }

    func testPacePredictsOnlyWhenAhead() throws {
        let now = Date(), reset = now.addingTimeInterval(2.5 * 3600)
        let ahead = try XCTUnwrap(UsagePace(window: UsageWindow(id: "five_hour", title: "5 hours", usedPercent: 80, resetsAt: reset, durationMinutes: 300), now: now))
        XCTAssertEqual(ahead.expectedPercent, 50, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(ahead.runsOutAt).timeIntervalSince(now), -2.5 * 3600 + 2.5 * 3600 * 100 / 80, accuracy: 1)
        XCTAssertNil(UsagePace(window: UsageWindow(id: "x", title: "x", usedPercent: 40, resetsAt: reset, durationMinutes: 300), now: now)?.runsOutAt)
        XCTAssertNil(UsagePace(window: UsageWindow(id: "x", title: "x", usedPercent: 40, resetsAt: nil, durationMinutes: 300), now: now))
        XCTAssertTrue(Moment.allCases.allSatisfy { !$0.hint.isEmpty && $0.hint.count <= 28 })
        XCTAssertTrue(Quips.candidates(.init(activity: .working, lowFuel: true)).contains("Sweating in binary."))
    }
}
