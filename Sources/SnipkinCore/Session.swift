import Foundation
import CryptoKit
import Darwin

public enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex
    public var id: String { rawValue }
    public var title: String { self == .claude ? "Claude Code" : "Codex" }
}
public enum Activity: String, Codable, CaseIterable, Sendable {
    case working, thinking, waiting, done, idle, unknown
    public var title: String {
        switch self {
        case .working: return "Working"
        case .thinking: return "Thinking"
        case .waiting: return "Needs you"
        case .done: return "Done"
        case .idle: return "Idle"
        case .unknown: return "Unknown"
        }
    }
    public var priority: Int {
        switch self { case .waiting: return 6; case .working: return 5; case .thinking: return 4; case .done: return 3; case .idle: return 2; case .unknown: return 1 }
    }
}
public struct Session: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(provider.rawValue):\(sessionID)" }
    public var sessionID: String
    public var provider: Provider
    public var cwd: String
    public var activity: Activity
    public var detail: String
    public var updatedAt: Date
    public var pid: Int32?
    public var appBundlePath: String?
    public var model: String?
    public var project: String { cwd.isEmpty ? "Unknown project" : URL(fileURLWithPath: cwd).lastPathComponent }
    public init(sessionID: String, provider: Provider, cwd: String, activity: Activity, detail: String, updatedAt: Date = Date(), pid: Int32? = nil, appBundlePath: String? = nil, model: String? = nil) {
        self.sessionID = sessionID; self.provider = provider; self.cwd = cwd; self.activity = activity; self.detail = detail; self.updatedAt = updatedAt; self.pid = pid; self.appBundlePath = appBundlePath
        self.model = model
    }
    public func effectiveActivity(now: Date) -> Activity {
        let age = now.timeIntervalSince(updatedAt)
        if age > 6 * 3600 { return .unknown }
        if activity == .done && age > 15 { return .idle }
        return activity
    }
}
enum CoreError: Error { case invalidPayload, invalidConfiguration, lockUnavailable }

// Short, bounded lock attempts keep lifecycle hooks from delaying their agent.
func withFileLock<T>(at url: URL, _ body: () throws -> T) throws -> T {
    let fd = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw CoreError.lockUnavailable }
    defer { close(fd) }
    var acquired = false
    for _ in 0..<20 {
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { acquired = true; break }
        usleep(5000)
    }
    guard acquired else { throw CoreError.lockUnavailable }
    defer { flock(fd, LOCK_UN) }
    return try body()
}
public struct SessionFiles: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public static var defaultDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["SNIPKIN_DATA_DIR"], !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Snipkin/sessions", isDirectory: true)
    }
    public func load(now: Date = Date()) -> [Session] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { file -> Session? in
            guard (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  let data = try? Data(contentsOf: file), let session = try? JSONDecoder().decode(Session.self, from: data) else { return nil }
            if now.timeIntervalSince(session.updatedAt) >= 24 * 3600 {
                // A hook may replace this record after our read. Revalidate under its lock.
                try? withFileLock(at: directory.appendingPathComponent(".lock")) {
                    guard let currentData = try? Data(contentsOf: file),
                          let current = try? JSONDecoder().decode(Session.self, from: currentData),
                          current == session, now.timeIntervalSince(current.updatedAt) >= 24 * 3600 else { return }
                    try FileManager.default.removeItem(at: file)
                }
                return nil
            }
            if let pid = session.pid, pid <= 1 || (kill(pid, 0) != 0 && errno == ESRCH) { return nil }
            return session
        }.sorted { a, b in
            let ap = a.effectiveActivity(now: now).priority, bp = b.effectiveActivity(now: now).priority
            return ap == bp ? a.updatedAt > b.updatedAt : ap > bp
        }
    }
    public func ingest(data: Data, provider: Provider, pid: Int32? = nil, appBundlePath: String? = nil, now: Date = Date()) throws {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = value["session_id"] as? String, !sessionID.isEmpty, sessionID.utf8.count <= 1024,
              let event = value["hook_event_name"] as? String else { throw CoreError.invalidPayload }
        let activity: Activity
        switch event {
        case "SessionStart", "Interrupt": activity = .idle
        case "UserPromptSubmit", "PostToolUse": activity = .thinking
        case "PreToolUse": activity = ["AskUserQuestion", "request_user_input"].contains(value["tool_name"] as? String ?? "") ? .waiting : .working
        case "PermissionRequest": activity = .waiting
        case "Stop": activity = .done
        case "SessionEnd": activity = .idle
        case "PostToolUseFailure": guard provider == .claude else { return }; activity = .thinking
        case "StopFailure": guard provider == .claude else { return }; activity = .idle
        case "Notification":
            guard provider == .claude, ["permission_prompt", "idle_prompt"].contains(value["notification_type"] as? String ?? "") else { return }
            activity = .waiting
        default: return
        }
        let detail: String
        switch event {
        case "PermissionRequest": detail = "Permission needed"
        case "PreToolUse":
            switch value["tool_name"] as? String {
            case "AskUserQuestion", "request_user_input": detail = "A question for you"
            case "Read", "read_file", "Grep", "Glob": detail = "Reading files"
            case "Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch": detail = "Editing files"
            case "Bash", "exec_command", "shell", "local_shell": detail = "Running command"
            case "WebSearch", "WebFetch", "web_search": detail = "Searching the web"
            case "Task", "Agent": detail = "Delegating to a helper"
            default: detail = "Using tool"
            }
        case "UserPromptSubmit", "PostToolUse": detail = "Preparing response"
        case "PostToolUseFailure": detail = "Recovering from an error"
        case "Stop": detail = "Response complete"
        case "SessionStart", "Interrupt": detail = "Ready for a new task"
        default: detail = activity.title
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let digest = SHA256.hash(data: Data("\(provider.rawValue):\(sessionID)".utf8)).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent(digest + ".json")
        try withFileLock(at: directory.appendingPathComponent(".lock")) {
            let previous = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
            if let previous, previous.updatedAt > now { return }
            if event == "SessionEnd" {
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                return
            }
            let cwd = String((value["cwd"] as? String ?? previous?.cwd ?? "").prefix(4096))
            let model = (value["model"] as? String).map { String($0.prefix(100)) } ?? previous?.model
            let session = Session(sessionID: sessionID, provider: provider, cwd: cwd, activity: activity, detail: detail, updatedAt: now, pid: pid ?? previous?.pid, appBundlePath: appBundlePath ?? previous?.appBundlePath, model: model)
            try JSONEncoder().encode(session).write(to: file, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }
}
