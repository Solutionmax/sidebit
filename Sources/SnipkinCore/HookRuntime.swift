import Foundation
import Darwin

public enum HookRuntime {
    public static func run(arguments: [String] = CommandLine.arguments) -> Int32? {
        guard arguments.count > 1 else { return nil }
        let action = arguments[1]
        if action == "--dump-state" {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(SessionFiles(directory: SessionFiles.defaultDirectory).load()) {
                FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
            }
            return 0
        }
        if action == "--statusline" {
            let data = (try? FileHandle.standardInput.read(upToCount: StatusLine.maximumInput)) ?? Data()
            FileHandle.standardOutput.write(Data((StatusLine.run(input: data) + "\n").utf8))
            return 0
        }
        if action == "--install-statusline" || action == "--uninstall-statusline" {
            let installer = HookInstaller(executable: URL(fileURLWithPath: arguments[0]).standardizedFileURL)
            do {
                if action == "--install-statusline" { try installer.installStatusLine() } else { try installer.uninstallStatusLine() }
                return 0
            } catch {
                FileHandle.standardError.write(Data("Sidebit could not update the Claude Code status line. Check ~/.claude/settings.json.\n".utf8))
                return 1
            }
        }
        guard ["--hook", "--install-hooks", "--uninstall-hooks"].contains(action) else { return nil }
        guard arguments.count > 2, let provider = Provider(rawValue: arguments[2]) else { return action == "--hook" ? 0 : 1 }
        if action == "--hook" {
            // Read a bounded payload; never print hook input or errors to agent streams.
            if let data = try? FileHandle.standardInput.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
                let source = sourceProcess(provider)
                try? SessionFiles(directory: SessionFiles.defaultDirectory).ingest(data: data, provider: provider, pid: source.pid, appBundlePath: source.app)
                recordJournal(data, provider: provider)
            }
            return 0
        }
        do {
            let installer = HookInstaller(executable: URL(fileURLWithPath: arguments[0]).standardizedFileURL)
            if action == "--install-hooks" { _ = try installer.install(provider) } else { try installer.uninstall(provider) }
            return 0
        } catch {
            FileHandle.standardError.write(Data("Sidebit could not update hook configuration. Check its format and permissions.\n".utf8))
            return 1
        }
    }
    /// Counts only the event kind and tool name. Prompts, arguments and results are never read.
    static func recordJournal(_ data: Data, provider: Provider, journal: Journal = Journal(directory: Journal.defaultDirectory), now: Date = Date()) {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let event = value["hook_event_name"] as? String else { return }
        let cwd = value["cwd"] as? String ?? ""
        _ = try? journal.record(event: event, tool: value["tool_name"] as? String, provider: provider,
                            project: cwd.isEmpty ? "" : URL(fileURLWithPath: cwd).lastPathComponent, now: now)
    }
    // Kernel process paths and parent IDs only; no argv, environment, or transcripts.
    private static func sourceProcess(_ provider: Provider) -> (pid: Int32?, app: String?) {
        var current = getppid(), foundPID: Int32?, app: String?
        var seen = Set<Int32>()
        for _ in 0..<32 {
            guard current > 1, seen.insert(current).inserted else { break }
            var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let count = proc_pidpath(current, &buffer, UInt32(buffer.count))
            if count > 0 {
                let path = String(cString: buffer)
                let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
                if name == provider.rawValue && foundPID == nil { foundPID = current }
                if app == nil, let range = path.range(of: ".app/") { app = String(path[..<range.lowerBound]) + ".app" }
            }
            var info = proc_bsdinfo()
            guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { break }
            current = Int32(info.pbi_ppid)
        }
        return (foundPID, app)
    }
}
