import XCTest
import Darwin
@testable import SnipkinCore

final class CoreTests: XCTestCase {
    func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func event(_ name: String, id: String = "../../escape", extra: [String: Any] = [:]) throws -> Data {
        var value: [String: Any] = ["hook_event_name": name, "session_id": id, "cwd": "/work/project", "prompt": "TOP SECRET"]
        value.merge(extra) { _, new in new }
        return try JSONSerialization.data(withJSONObject: value)
    }
    func testLifecyclePrivacyAndExpiry() throws {
        let dir = try temporary(), store = SessionFiles(directory: dir), now = Date()
        try store.ingest(data: event("PermissionRequest"), provider: .claude, now: now)
        XCTAssertEqual(store.load(now: now).first?.activity, .waiting)
        XCTAssertEqual(store.load(now: now).first?.project, "project")
        XCTAssertGreaterThan(Activity.waiting.priority, Activity.working.priority)
        try store.ingest(data: event("MadeUp"), provider: .claude, now: now)
        XCTAssertEqual(store.load(now: now).first?.activity, .waiting)
        try store.ingest(data: event("Stop"), provider: .claude, now: now)
        let session = try XCTUnwrap(store.load(now: now).first)
        XCTAssertEqual(session.effectiveActivity(now: now), .done)
        XCTAssertEqual(session.effectiveActivity(now: now.addingTimeInterval(16)), .idle)
        XCTAssertEqual(session.effectiveActivity(now: now.addingTimeInterval(22000)), .unknown)
        XCTAssertTrue(store.load(now: now.addingTimeInterval(90000)).isEmpty)
        for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            XCTAssertFalse(try String(contentsOf: file).contains("TOP SECRET"))
            XCTAssertEqual(file.deletingPathExtension().lastPathComponent.count, 64)
        }
        try store.ingest(data: event("SessionEnd"), provider: .claude, now: now)
        XCTAssertTrue(store.load(now: now).isEmpty)
    }
    func testModelMetadataSurvivesEventsWithoutModel() throws {
        let store = SessionFiles(directory: try temporary())
        try store.ingest(data: event("SessionStart", extra: ["model": "example-model"]), provider: .codex)
        try store.ingest(data: event("PreToolUse"), provider: .codex)
        XCTAssertEqual(store.load().first?.model, "example-model")
        try store.ingest(data: event("SessionStart", id: "without-model"), provider: .claude)
        XCTAssertNil(store.load().first { $0.sessionID == "without-model" }?.model)
    }
    func testMappingsIsolationAndDeadPID() throws {
        let store = SessionFiles(directory: try temporary())
        let mappings: [(String, Activity)] = [("SessionStart", .idle), ("UserPromptSubmit", .thinking), ("PreToolUse", .working), ("PostToolUse", .thinking), ("Interrupt", .idle)]
        for (name, expected) in mappings {
            try store.ingest(data: event(name), provider: .codex)
            XCTAssertEqual(store.load().first?.activity, expected)
        }
        try store.ingest(data: event("PreToolUse", extra: ["tool_name": "request_user_input"]), provider: .codex)
        XCTAssertEqual(store.load().first?.activity, .waiting)
        try store.ingest(data: event("Notification", extra: ["notification_type": "idle_prompt"]), provider: .claude)
        XCTAssertEqual(store.load().count, 2)
        try store.ingest(data: event("SessionStart", id: "dead"), provider: .claude, pid: 2147483647)
        XCTAssertEqual(store.load().count, 2)
        XCTAssertThrowsError(try store.ingest(data: Data("{".utf8), provider: .claude))
    }
    func testHookReadsFragmentedInputWithoutPersistingSecrets() throws {
        let dir = try temporary()
        let old = ProcessInfo.processInfo.environment["SNIPKIN_DATA_DIR"]
        setenv("SNIPKIN_DATA_DIR", dir.path, 1)
        defer { if let old { setenv("SNIPKIN_DATA_DIR", old, 1) } else { unsetenv("SNIPKIN_DATA_DIR") } }
        let pipe = Pipe(), saved = dup(STDIN_FILENO)
        dup2(pipe.fileHandleForReading.fileDescriptor, STDIN_FILENO)
        defer { dup2(saved, STDIN_FILENO); close(saved) }
        let payload = try event("PreToolUse")
        pipe.fileHandleForWriting.write(payload.prefix(1))
        let done = expectation(description: "writer")
        DispatchQueue.global().async {
            usleep(30000)
            pipe.fileHandleForWriting.write(payload.dropFirst())
            try? pipe.fileHandleForWriting.close()
            done.fulfill()
        }
        XCTAssertEqual(HookRuntime.run(arguments: ["Snipkin", "--hook", "claude"]), 0)
        wait(for: [done], timeout: 2)
        XCTAssertEqual(SessionFiles(directory: dir).load().first?.activity, .working)
    }
    func testConcurrentWritesRemainCompleteAndNewestWins() throws {
        let store = SessionFiles(directory: try temporary()), now = Date()
        let payload = try event("PreToolUse")
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            try? store.ingest(data: payload, provider: .claude, now: now.addingTimeInterval(Double(index)))
        }
        try store.ingest(data: event("PermissionRequest"), provider: .claude, now: now.addingTimeInterval(30))
        try store.ingest(data: event("Stop"), provider: .claude, now: now)
        try store.ingest(data: event("SessionEnd"), provider: .claude, now: now)
        XCTAssertEqual(store.load(now: now).count, 1)
        XCTAssertEqual(store.load(now: now).first?.activity, .waiting)
    }
    func testEnglishSanitizedDetailsAndMovedInstallation() throws {
        let store = SessionFiles(directory: try temporary())
        for (tool, detail) in [("Read", "Reading files"), ("apply_patch", "Editing files"), ("exec_command", "Running command"), ("secret-custom-tool", "Using tool"), ("AskUserQuestion", "A question for you")] {
            try store.ingest(data: event("PreToolUse", extra: ["tool_name": tool]), provider: .claude)
            XCTAssertEqual(store.load().first?.detail, detail)
        }
        XCTAssertEqual(Activity.waiting.title, "Needs you")
        let home = try temporary()
        let old = HookInstaller(home: home, executable: URL(fileURLWithPath: "/old/Snipkin"))
        let moved = HookInstaller(home: home, executable: URL(fileURLWithPath: "/new/Snipkin"))
        _ = try old.install(.codex)
        XCTAssertFalse(moved.isInstalled(.codex))
        _ = try moved.install(.codex)
        XCTAssertTrue(moved.isInstalled(.codex))
        XCTAssertFalse(old.isInstalled(.codex))
        try old.uninstall(.codex)
        XCTAssertFalse(moved.isInstalled(.codex))
    }
    func testExpiredRecordsArePrunedAndFreshReplacementSurvives() throws {
        let directory = try temporary(), store = SessionFiles(directory: directory), now = Date()
        try store.ingest(data: event("Stop"), provider: .claude, now: now.addingTimeInterval(-90000))
        XCTAssertTrue(store.load(now: now).isEmpty)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasSuffix(".json") })
        try store.ingest(data: event("Stop"), provider: .claude, now: now.addingTimeInterval(-90000))
        try store.ingest(data: event("PermissionRequest"), provider: .claude, now: now)
        XCTAssertEqual(store.load(now: now).first?.activity, .waiting)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }.count, 1)

        let racingDirectory = try temporary(), racingStore = SessionFiles(directory: racingDirectory)
        try racingStore.ingest(data: event("Stop"), provider: .claude, now: now.addingTimeInterval(-90000))
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: racingDirectory, includingPropertiesForKeys: nil).first { $0.pathExtension == "json" })
        let pruned = expectation(description: "pruner finished")
        try withFileLock(at: racingDirectory.appendingPathComponent(".lock")) {
            DispatchQueue.global().async {
                _ = racingStore.load(now: now)
                pruned.fulfill()
            }
            usleep(30000)
            let fresh = Session(sessionID: "../../escape", provider: .claude, cwd: "/work/project", activity: .waiting, detail: "Needs you", updatedAt: now)
            try JSONEncoder().encode(fresh).write(to: file, options: .atomic)
        }
        wait(for: [pruned], timeout: 2)
        XCTAssertEqual(racingStore.load(now: now).first?.activity, .waiting)
    }
    func testInstallerPreservesAndReverses() throws {
        for provider in Provider.allCases {
            let home = try temporary(), folder = home.appendingPathComponent(provider == .claude ? ".claude" : ".codex")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let config = folder.appendingPathComponent(provider == .claude ? "settings.json" : "hooks.json")
            let original = Data(#"{"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo existing"}]}]}}"#.utf8)
            try original.write(to: config)
            let installer = HookInstaller(home: home, executable: URL(fileURLWithPath: "/Applications/It's Snipkin.app/Contents/MacOS/Snipkin"))
            let backup = try installer.install(provider)
            XCTAssertEqual(try Data(contentsOf: backup), original)
            XCTAssertTrue(installer.isInstalled(provider))
            let installed = try Data(contentsOf: config)
            _ = try installer.install(provider)
            XCTAssertEqual(try Data(contentsOf: config), installed)
            try installer.uninstall(provider)
            XCTAssertFalse(installer.isInstalled(provider))
            let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
            XCTAssertEqual(value["theme"] as? String, "dark")
            XCTAssertTrue(String(data: try Data(contentsOf: config), encoding: .utf8)!.contains("echo existing"))
            try Data("broken".utf8).write(to: config)
            XCTAssertThrowsError(try installer.install(provider))
            XCTAssertEqual(try String(contentsOf: config), "broken")
        }
    }

    func testLegacyMaatjeHooksAreReplacedWithoutDuplicates() throws {
        let home = try temporary()
        let folder = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("settings.json")
        let old = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"'/Applications/Maatje.app/Contents/MacOS/Maatje' --hook claude # maatje-lifecycle-v1"},{"type":"command","command":"echo unrelated"}]}]}}"#
        try Data(old.utf8).write(to: url)
        let installer = HookInstaller(home: home, executable: URL(fileURLWithPath: "/Applications/Snipkin.app/Contents/MacOS/Snipkin"))
        _ = try installer.install(.claude)
        let updated = try String(contentsOf: url)
        XCTAssertFalse(updated.contains("maatje-lifecycle-v1"))
        XCTAssertTrue(updated.contains("echo unrelated"))
        XCTAssertTrue(installer.isInstalled(.claude))
    }
}
