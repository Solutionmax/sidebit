import Foundation
import Darwin

/// Claude Code status-line integration: Bit rides along in the terminal and reads first-party `rate_limits`.
public enum StatusLine {
    public static let marker = "# sidebit-statusline-v1"
    static let maximumInput = 1_048_576

    public struct Input: Equatable, Sendable {
        public var sessionID: String?
        public var project: String
        public var usage: UsageSnapshot?
        public var linesAdded: Int?, linesRemoved: Int?
        public var contextPercent: Double?
    }

    public static func parse(_ data: Data, now: Date = Date()) -> Input? {
        guard data.count <= maximumInput, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let workspace = root["workspace"] as? [String: Any]
        let cwd = (workspace?["project_dir"] as? String) ?? (workspace?["current_dir"] as? String) ?? (root["cwd"] as? String) ?? ""
        var input = Input(sessionID: (root["session_id"] as? String).flatMap { $0.isEmpty || $0.utf8.count > 1024 ? nil : $0 },
                          project: cwd.isEmpty ? "" : URL(fileURLWithPath: cwd).lastPathComponent)
        if let cost = root["cost"] as? [String: Any] {
            input.linesAdded = integer(cost["total_lines_added"]); input.linesRemoved = integer(cost["total_lines_removed"])
        }
        input.contextPercent = number((root["context_window"] as? [String: Any])?["used_percentage"]).flatMap { (0...100).contains($0) ? $0 : nil }
        if let limits = root["rate_limits"] as? [String: Any] {
            var windows: [UsageWindow] = []
            for (key, title, minutes) in [("five_hour", "5 hours", 300), ("seven_day", "7 days", 10080)] {
                guard let item = limits[key] as? [String: Any], let used = number(item["used_percentage"]), (0...100).contains(used) else { continue }
                let reset = number(item["resets_at"]).flatMap { $0 > 0 && $0 < 253_402_300_800 ? Date(timeIntervalSince1970: $0) : nil }
                windows.append(UsageWindow(id: key, title: title, usedPercent: used, resetsAt: reset, durationMinutes: minutes))
            }
            if !windows.isEmpty { input.usage = UsageSnapshot(provider: .claude, windows: windows, fetchedAt: now, source: "Claude Code status line") }
        }
        return input
    }

    public static let faces: [Activity: String] = [
        .working: "(•ᴗ•)⌨", .thinking: "(•_•)?", .waiting: "(°o°)/", .done: "\\(^ᴗ^)/", .idle: "(-.-)zZ", .unknown: "(•_•?)"
    ]

    /// One short line. Colors are plain 256-color ANSI, which Claude Code renders.
    public static func render(activity: Activity, detail: String, input: Input?, showUsage: Bool, now: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let seed = Int(now.timeIntervalSince1970 / 120) &+ (input?.sessionID?.utf8.reduce(0) { $0 &+ Int($1) } ?? 0)
        let quip = Quips.line(.init(activity: activity, detail: detail, provider: .claude, hour: hour), seed: seed)
        var parts = ["\u{1B}[38;5;173m\(faces[activity] ?? "(•ᴗ•)")\u{1B}[0m Bit", "\u{1B}[2m\(quip)\u{1B}[0m"]
        if showUsage, let usage = input?.usage {
            parts += usage.windows.map { "\($0.id == "five_hour" ? "5h" : "7d") \(Int($0.usedPercent.rounded()))%" }
        }
        return parts.joined(separator: " · ")
    }

    /// Runs as the `statusLine` command. Never fails loudly; a broken status line would be worse than none.
    public static func run(input data: Data, config: StatusLineConfig = .load(), sessions: SessionFiles = SessionFiles(directory: SessionFiles.defaultDirectory),
                           journal: Journal = Journal(directory: Journal.defaultDirectory), usage: UsageStore = UsageStore(), now: Date = Date()) -> String {
        let input = parse(data, now: now)
        if let input {
            if let snapshot = input.usage { try? usage.save(snapshot) }
            if let id = input.sessionID, let added = input.linesAdded, let removed = input.linesRemoved {
                _ = try? journal.recordLines(session: id, added: added, removed: removed, project: input.project, now: now)
            }
        }
        var lines: [String] = []
        if let command = config.wrappedCommand, let output = runWrapped(command, input: data), !output.isEmpty { lines.append(output) }
        if config.showBit {
            let session = input?.sessionID.flatMap { id in sessions.load(now: now).first { $0.provider == .claude && $0.sessionID == id } }
            lines.append(render(activity: session?.effectiveActivity(now: now) ?? .idle, detail: session?.detail ?? "", input: input,
                                showUsage: config.wrappedCommand == nil, now: now))
        }
        return lines.joined(separator: "\n")
    }

    /// Runs the user's previous status line in its own process group, so a hung pipeline is killed as a whole.
    static func runWrapped(_ command: String, input: Data, timeout: TimeInterval = 5) -> String? {
        var toChild: [Int32] = [0, 0], fromChild: [Int32] = [0, 0]
        guard pipe(&toChild) == 0 else { return nil }
        guard pipe(&fromChild) == 0 else { close(toChild[0]); close(toChild[1]); return nil }
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_adddup2(&actions, toChild[0], STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, fromChild[1], STDOUT_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        for fd in toChild + fromChild { posix_spawn_file_actions_addclose(&actions, fd) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)
        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/sh"), strdup("-c"), strdup(command), nil]
        defer { argv.forEach { free($0) } }
        let spawned = posix_spawn(&pid, "/bin/sh", &actions, &attributes, argv, environ)
        close(toChild[0]); close(fromChild[1])
        guard spawned == 0 else { close(toChild[1]); close(fromChild[0]); return nil }
        let output = OutputBuffer(), drained = DispatchSemaphore(value: 0)
        let reader = FileHandle(fileDescriptor: fromChild[0], closeOnDealloc: true)
        DispatchQueue.global(qos: .userInitiated).async { output.set(reader.readDataToEndOfFile()); drained.signal() }
        let writer = FileHandle(fileDescriptor: toChild[1], closeOnDealloc: true)
        signal(SIGPIPE, SIG_IGN)
        try? writer.write(contentsOf: input)
        try? writer.close()
        guard drained.wait(timeout: .now() + timeout) == .success else {
            kill(-pid, SIGKILL)
            waitpid(pid, nil, 0)
            return nil
        }
        waitpid(pid, nil, 0)
        return String(data: output.value.prefix(65_536), encoding: .utf8)?.trimmingCharacters(in: .newlines)
    }

    static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    static func integer(_ value: Any?) -> Int? { number(value).flatMap { $0 >= 0 && $0 < 1e9 ? Int($0) : nil } }
}

/// Stored beside Sidebit's data, never inside Claude's settings, so uninstalling restores the user's exact status line.
public struct StatusLineConfig: Codable, Equatable, Sendable {
    public var original: String?
    public var showBit = true
    public init(original: String? = nil, showBit: Bool = true) { self.original = original; self.showBit = showBit }

    /// The previous `statusLine.command`, when it was a command status line.
    public var wrappedCommand: String? {
        guard let original, let data = original.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["type"] as? String == "command", let command = value["command"] as? String, !command.isEmpty else { return nil }
        return command
    }

    public static func file(_ root: URL = StoragePaths.root) -> URL { root.appendingPathComponent("statusline.json") }
    public static func load(_ root: URL = StoragePaths.root) -> StatusLineConfig {
        guard let data = try? Data(contentsOf: file(root)), let value = try? JSONDecoder().decode(StatusLineConfig.self, from: data) else { return StatusLineConfig() }
        return value
    }
    public func save(_ root: URL = StoragePaths.root) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(self).write(to: Self.file(root), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.file(root).path)
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ value: Data) { lock.lock(); data = value; lock.unlock() }
    var value: Data { lock.lock(); defer { lock.unlock() }; return data }
}
