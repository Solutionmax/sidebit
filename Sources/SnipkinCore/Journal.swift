import Foundation
import CryptoKit

/// Local, per-day counters. Only event kinds, counts, times and project folder names; never prompts or tool content.
public struct DayJournal: Codable, Equatable, Sendable {
    public var day: String
    public var turns = 0, prompts = 0, asks = 0, edits = 0, commands = 0, reads = 0, tools = 0, failures = 0, sessions = 0
    public var claudeEvents = 0, codexEvents = 0
    public var firstAt: Date?, lastAt: Date?
    public var projects: [String] = []
    /// Cumulative lines per session from the Claude Code status line, keyed by a session digest.
    public var sessionLines: [String: [Int]] = [:]
    public var nightOwl = false, earlyBird = false, weekend = false
    /// Counted events per local hour, for the day ribbon.
    public var hours = [Int](repeating: 0, count: 24)
    public var boops = 0, carries = 0
    public var fridayLateCommand = false
    public init(day: String) { self.day = day }

    // Older files lack newer fields; decode what exists so an upgrade never resets today.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        func int(_ key: CodingKeys) -> Int { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? 0 }
        func flag(_ key: CodingKeys) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: key)) ?? false }
        (turns, prompts, asks, edits, commands) = (int(.turns), int(.prompts), int(.asks), int(.edits), int(.commands))
        (reads, tools, failures, sessions) = (int(.reads), int(.tools), int(.failures), int(.sessions))
        (claudeEvents, codexEvents) = (int(.claudeEvents), int(.codexEvents))
        firstAt = try? c.decodeIfPresent(Date.self, forKey: .firstAt)
        lastAt = try? c.decodeIfPresent(Date.self, forKey: .lastAt)
        projects = (try? c.decodeIfPresent([String].self, forKey: .projects)) ?? []
        sessionLines = (try? c.decodeIfPresent([String: [Int]].self, forKey: .sessionLines)) ?? [:]
        (nightOwl, earlyBird, weekend) = (flag(.nightOwl), flag(.earlyBird), flag(.weekend))
        let stored = (try? c.decodeIfPresent([Int].self, forKey: .hours)) ?? []
        hours = stored.count == 24 ? stored : [Int](repeating: 0, count: 24)
        (boops, carries, fridayLateCommand) = (int(.boops), int(.carries), flag(.fridayLateCommand))
    }

    /// The busiest local hour, when anything happened.
    public var busiestHour: Int? { hours.max().flatMap { $0 > 0 ? hours.firstIndex(of: $0) : nil } }

    public var linesAdded: Int { sessionLines.values.reduce(0) { $0 + ($1.first ?? 0) } }
    public var linesRemoved: Int { sessionLines.values.reduce(0) { $0 + ($1.dropFirst().first ?? 0) } }
    public var activeSpan: TimeInterval { guard let firstAt, let lastAt else { return 0 }; return lastAt.timeIntervalSince(firstAt) }
    public var isEmpty: Bool { turns == 0 && prompts == 0 && tools == 0 && sessions == 0 }
}

public struct MomentRecord: Codable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let project: String?
    public var seen: Bool
    public init(id: String, date: Date, project: String?, seen: Bool) { self.id = id; self.date = date; self.project = project; self.seen = seen }
}

public struct Journal: Sendable {
    public let directory: URL
    private static let maximumProjects = 50, maximumSessions = 200
    public init(directory: URL) { self.directory = directory }

    public static var defaultDirectory: URL { StoragePaths.directory("journal") }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func file(_ day: String) -> URL { directory.appendingPathComponent(day + ".json") }
    private var momentsFile: URL { directory.appendingPathComponent("moments.json") }
    private var lifetimeFile: URL { directory.appendingPathComponent("lifetime.json") }

    /// Running totals since Bit arrived. The first call sums existing day files once.
    public func lifetime(bootstrap: Bool = false) -> Lifetime {
        if let data = try? Data(contentsOf: lifetimeFile), let value = try? JSONDecoder().decode(Lifetime.self, from: data) { return value }
        guard bootstrap else { return Lifetime() }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var total = Lifetime()
        for file in files where file.pathExtension == "json" && file.lastPathComponent.hasPrefix("20") {
            total.add(from: DayJournal(day: ""), to: read(file.deletingPathExtension().lastPathComponent))
        }
        return total
    }

    public func day(_ date: Date = Date()) -> DayJournal { read(Self.dayKey(date)) }
    private func read(_ key: String) -> DayJournal {
        guard let data = try? Data(contentsOf: file(key)), let value = try? JSONDecoder.journal.decode(DayJournal.self, from: data) else { return DayJournal(day: key) }
        return value
    }
    public func moments() -> [MomentRecord] {
        guard let data = try? Data(contentsOf: momentsFile), let value = try? JSONDecoder.journal.decode([MomentRecord].self, from: data) else { return [] }
        return value
    }

    /// Consecutive days with at least one finished turn, ending on `date`.
    public func streak(endingOn date: Date = Date(), calendar: Calendar = .current) -> Int {
        var count = 0, cursor = date
        while count < 30, read(Self.dayKey(cursor, calendar: calendar)).turns > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// Seven days ending on `date`, oldest first. Empty days are included.
    public func week(endingOn date: Date = Date(), calendar: Calendar = .current) -> [DayJournal] {
        (0..<7).reversed().compactMap { offset in calendar.date(byAdding: .day, value: -offset, to: date) }.map { read(Self.dayKey($0, calendar: calendar)) }
    }

    /// Records one lifecycle event and returns moments unlocked by it.
    @discardableResult
    public func record(event: String, tool: String?, provider: Provider, project: String, now: Date = Date(), calendar: Calendar = .current) throws -> [Moment] {
        try update(now: now, calendar: calendar, project: project) { day in
            switch event {
            case "SessionStart": day.sessions += 1
            case "UserPromptSubmit": day.prompts += 1
            case "Stop": day.turns += 1
            case "PermissionRequest": day.asks += 1
            case "PostToolUseFailure": day.failures += 1
            case "PreToolUse":
                day.tools += 1
                switch tool {
                case "Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch": day.edits += 1
                case "Bash", "exec_command", "shell", "local_shell":
                    day.commands += 1
                    if calendar.component(.weekday, from: now) == 6 && calendar.component(.hour, from: now) >= 16 { day.fridayLateCommand = true }
                case "Read", "read_file", "Grep", "Glob": day.reads += 1
                case "AskUserQuestion", "request_user_input": day.asks += 1
                default: break
                }
            default: return false
            }
            if provider == .claude { day.claudeEvents += 1 } else { day.codexEvents += 1 }
            let hour = calendar.component(.hour, from: now)
            day.hours[hour] += 1
            if hour < 5 { day.nightOwl = true } else if hour < 7 { day.earlyBird = true }
            if calendar.isDateInWeekend(now) { day.weekend = true }
            return true
        }
    }

    public enum Interaction: Sendable { case boop, carry }
    /// Playing with Bit counts too.
    @discardableResult
    public func record(_ interaction: Interaction, now: Date = Date(), calendar: Calendar = .current) throws -> [Moment] {
        try update(now: now, calendar: calendar, project: "", touchesTime: false) { day in
            if interaction == .boop { day.boops += 1 } else { day.carries += 1 }
            return true
        }
    }

    /// Stores cumulative line counts for one status-line session.
    @discardableResult
    public func recordLines(session: String, added: Int, removed: Int, project: String, now: Date = Date(), calendar: Calendar = .current) throws -> [Moment] {
        let key = SHA256.hash(data: Data(session.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        let values = [max(0, min(added, 10_000_000)), max(0, min(removed, 10_000_000))]
        return try update(now: now, calendar: calendar, project: project, touchesTime: false) { day in
            guard day.sessionLines[key] != values else { return false }
            guard day.sessionLines[key] != nil || day.sessionLines.count < Self.maximumSessions else { return false }
            day.sessionLines[key] = values
            return true
        }
    }

    /// Marks one moment, or all when `id` is nil, as celebrated.
    public func markSeen(id: String? = nil) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try withFileLock(at: directory.appendingPathComponent(".lock")) {
            let records = moments()
            guard records.contains(where: { !$0.seen && (id == nil || $0.id == id) }) else { return }
            try write(records.map { var r = $0; if id == nil || r.id == id { r.seen = true }; return r }, to: momentsFile)
        }
    }

    private func update(now: Date, calendar: Calendar, project: String, touchesTime: Bool = true, _ change: (inout DayJournal) -> Bool) throws -> [Moment] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return try withFileLock(at: directory.appendingPathComponent(".lock")) {
            let key = Self.dayKey(now, calendar: calendar)
            var day = read(key)
            let before = day
            guard change(&day) else { return [] }
            var total = lifetime(bootstrap: true)
            total.add(from: before, to: day)
            try write(total, to: lifetimeFile)
            if touchesTime {
                if day.firstAt == nil || now < day.firstAt! { day.firstAt = now }
                if day.lastAt == nil || now > day.lastAt! { day.lastAt = now }
            }
            let name = String(project.prefix(80))
            if !name.isEmpty, !day.projects.contains(name), day.projects.count < Self.maximumProjects { day.projects.append(name) }
            try write(day, to: file(key))
            var records = moments()
            let known = Set(records.map(\.id))
            let fresh = Moment.earned(by: day, streak: streak(endingOn: now, calendar: calendar), lifetime: total).filter { !known.contains($0.rawValue) }
            guard !fresh.isEmpty else { return [] }
            records += fresh.map { MomentRecord(id: $0.rawValue, date: now, project: name.isEmpty ? nil : name, seen: false) }
            try write(records, to: momentsFile)
            return fresh
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

extension JSONDecoder {
    static var journal: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}

/// All Sidebit state lives under one folder. `SNIPKIN_DATA_DIR` isolates tests and keeps everything inside it.
public enum StoragePaths {
    public static var root: URL {
        if let path = ProcessInfo.processInfo.environment["SNIPKIN_DATA_DIR"], !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Snipkin", isDirectory: true)
    }
    public static func directory(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }
}

/// A week in numbers, for Friday's recap card.
public struct WeekSummary: Equatable, Sendable {
    public let days: [DayJournal]
    public init(days: [DayJournal]) { self.days = days }
    public var turns: Int { days.reduce(0) { $0 + $1.turns } }
    public var linesAdded: Int { days.reduce(0) { $0 + $1.linesAdded } }
    public var activeDays: Int { days.filter { !$0.isEmpty }.count }
    public var bestDay: DayJournal? { days.max { $0.turns < $1.turns }.flatMap { $0.turns > 0 ? $0 : nil } }
    public var claudeShare: Double? {
        let claude = days.reduce(0) { $0 + $1.claudeEvents }, codex = days.reduce(0) { $0 + $1.codexEvents }
        return claude + codex == 0 ? nil : Double(claude) / Double(claude + codex)
    }
    /// Latest hour anything happened, counting midnight to 5 AM as the night before.
    public var latestHour: Int? {
        days.flatMap { day in day.hours.indices.filter { day.hours[$0] > 0 }.map { $0 < 5 ? $0 + 24 : $0 } }.max().map { $0 % 24 }
    }
}

/// Where an allowance window "should" be if usage were spread evenly, and when it would run out at the current pace.
public struct UsagePace: Equatable, Sendable {
    public let expectedPercent: Double
    public let runsOutAt: Date?

    public init?(window: UsageWindow, now: Date = Date()) {
        guard let reset = window.resetsAt, let minutes = window.durationMinutes, minutes > 0, reset > now else { return nil }
        let duration = Double(minutes) * 60, start = reset.addingTimeInterval(-duration)
        let elapsed = min(duration, max(0, now.timeIntervalSince(start)))
        expectedPercent = elapsed / duration * 100
        // Only predict when clearly ahead of pace and with enough history to mean something.
        if window.usedPercent >= 5, window.usedPercent > expectedPercent + 5, elapsed > 0 {
            let exhaust = start.addingTimeInterval(elapsed * 100 / window.usedPercent)
            runsOutAt = exhaust < reset ? exhaust : nil
        } else { runsOutAt = nil }
    }
}

public struct Lifetime: Codable, Equatable, Sendable {
    public var turns = 0, commands = 0, edits = 0, activeDays = 0
    public init() {}
    mutating func add(from old: DayJournal, to new: DayJournal) {
        turns += max(0, new.turns - old.turns)
        commands += max(0, new.commands - old.commands)
        edits += max(0, new.edits - old.edits)
        if old.turns == 0 && new.turns > 0 { activeDays += 1 }
    }
}
