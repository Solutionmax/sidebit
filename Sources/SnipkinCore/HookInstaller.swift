import Foundation

public struct HookInstaller {
    private let home: URL
    private let executable: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, executable: URL) { self.home = home; self.executable = executable }
    private func config(_ provider: Provider) -> URL { home.appendingPathComponent(provider == .claude ? ".claude/settings.json" : ".codex/hooks.json") }
    private func events(_ provider: Provider) -> [String] {
        let common = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop", "SessionEnd"]
        return common + (provider == .claude ? ["PostToolUseFailure", "StopFailure", "Notification"] : ["Interrupt"])
    }
    private func command(_ provider: Provider) -> String {
        "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "' --hook " + provider.rawValue + " # snipkin-lifecycle-v1"
    }
    private func owned(_ handler: [String: Any], _ provider: Provider) -> Bool {
        guard handler["type"] as? String == "command", let value = handler["command"] as? String else { return false }
        return value.hasSuffix(" --hook \(provider.rawValue) # snipkin-lifecycle-v1")
            || value.hasSuffix(" --hook \(provider.rawValue) # maatje-lifecycle-v1")
    }
    private func read(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw CoreError.invalidConfiguration }
        if let hooks = root["hooks"] {
            guard let events = hooks as? [String: Any] else { throw CoreError.invalidConfiguration }
            for groups in events.values {
                guard let groups = groups as? [[String: Any]] else { throw CoreError.invalidConfiguration }
                for group in groups {
                    guard group["hooks"] is [[String: Any]] else { throw CoreError.invalidConfiguration }
                }
            }
        }
        return root
    }
    private func removingOwned(_ root: [String: Any], _ provider: Provider) -> [String: Any] {
        var result = root
        guard var hooks = root["hooks"] as? [String: Any] else { return result }
        for (event, rawGroups) in hooks {
            guard let groups = rawGroups as? [[String: Any]] else { continue }
            let remaining = groups.compactMap { group -> [String: Any]? in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let filtered = handlers.filter { !owned($0, provider) }
                if filtered.count == handlers.count { return group }
                if filtered.isEmpty { return nil }
                var copy = group; copy["hooks"] = filtered; return copy
            }
            if remaining.isEmpty && !groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = remaining }
        }
        result["hooks"] = hooks
        return result
    }
    @discardableResult public func install(_ provider: Provider) throws -> URL { try update(provider, installing: true) }
    public func uninstall(_ provider: Provider) throws { _ = try update(provider, installing: false) }
    public func isInstalled(_ provider: Provider) -> Bool {
        guard let root = try? read(config(provider)), let hooks = root["hooks"] as? [String: Any] else { return false }
        return events(provider).allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { $0["type"] as? String == "command" && $0["command"] as? String == command(provider) }
            }
        }
    }
    private func update(_ provider: Provider, installing: Bool) throws -> URL {
        try edit(config(provider), skipMissing: !installing) { original in
            var updated = removingOwned(original, provider)
            if installing {
                var hooks = updated["hooks"] as? [String: Any] ?? [:]
                for event in events(provider) {
                    var groups = hooks[event] as? [[String: Any]] ?? []
                    groups.append(["hooks": [["type": "command", "command": command(provider), "timeout": 2]]])
                    hooks[event] = groups
                }
                updated["hooks"] = hooks
            }
            return updated
        }
    }

    // MARK: Claude Code status line

    private var statusLineCommand: String {
        "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "' --statusline " + StatusLine.marker
    }
    private func ownsStatusLine(_ root: [String: Any]) -> Bool {
        ((root["statusLine"] as? [String: Any])?["command"] as? String)?.hasSuffix(" --statusline " + StatusLine.marker) == true
    }
    public func isStatusLineInstalled() -> Bool {
        guard let root = try? read(config(.claude)) else { return false }
        return ((root["statusLine"] as? [String: Any])?["command"] as? String) == statusLineCommand
    }
    /// Keeps an existing status line: Sidebit runs it first and prints its output unchanged.
    @discardableResult public func installStatusLine(state: URL = StoragePaths.root) throws -> URL {
        var config = StatusLineConfig.load(state)
        return try edit(self.config(.claude), skipMissing: false) { original in
            var updated = original
            if let existing = original["statusLine"], !ownsStatusLine(original) {
                let data = try JSONSerialization.data(withJSONObject: existing, options: [.sortedKeys])
                config.original = String(data: data, encoding: .utf8)
            }
            try config.save(state)
            var line = (original["statusLine"] as? [String: Any]) ?? [:]
            line["type"] = "command"
            line["command"] = statusLineCommand
            if line["refreshInterval"] == nil { line["refreshInterval"] = 10 }
            updated["statusLine"] = line
            return updated
        }
    }
    public func uninstallStatusLine(state: URL = StoragePaths.root) throws {
        var config = StatusLineConfig.load(state)
        var restored = false
        _ = try edit(self.config(.claude), skipMissing: true) { original in
            // Someone else owns the status line now: leave it, and keep the saved original for later.
            guard ownsStatusLine(original) else { return original }
            restored = true
            var updated = original
            if let text = config.original, let data = text.data(using: .utf8), let previous = try? JSONSerialization.jsonObject(with: data) {
                updated["statusLine"] = previous
            } else { updated.removeValue(forKey: "statusLine") }
            return updated
        }
        guard restored else { return }
        config.original = nil
        try config.save(state)
    }

    /// Locked read-modify-write with a private backup of the previous file.
    private func edit(_ url: URL, skipMissing: Bool, _ change: ([String: Any]) throws -> [String: Any]) throws -> URL {
        let fm = FileManager.default
        if skipMissing && !fm.fileExists(atPath: url.path) { return url }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return try withFileLock(at: url.appendingPathExtension("snipkin.lock")) {
            let original = try read(url)
            let updated = try change(original)
            guard !NSDictionary(dictionary: original).isEqual(to: updated) else { return url }
            var backup = url
            if fm.fileExists(atPath: url.path) {
                backup = url.appendingPathExtension("snipkin-backup-" + UUID().uuidString)
                try fm.copyItem(at: url, to: backup)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            }
            try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return backup
        }
    }
}
