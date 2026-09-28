import Foundation

public struct UsageWindow: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let title: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let durationMinutes: Int?
    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?, durationMinutes: Int?) {
        self.id = id; self.title = title; self.usedPercent = usedPercent
        self.resetsAt = resetsAt; self.durationMinutes = durationMinutes
    }
}
public struct UsageSnapshot: Equatable, Codable, Sendable {
    public let provider: Provider
    public let windows: [UsageWindow]
    public let fetchedAt: Date
    public let source: String
    public let plan: String?
    public let tokensToday: Int?
    public let model: String?
    public init(provider: Provider, windows: [UsageWindow], fetchedAt: Date = Date(), source: String, plan: String? = nil, tokensToday: Int? = nil, model: String? = nil) {
        self.provider = provider; self.windows = windows; self.fetchedAt = fetchedAt
        self.source = source; self.plan = plan; self.tokensToday = tokensToday; self.model = model
    }
}
public enum UsageFailure: Error, LocalizedError {
    case notSignedIn(String), unavailable(String), rateLimited(retryAfter: TimeInterval), needsKeychain
    public var errorDescription: String? {
        switch self {
        case .needsKeychain: return "Claude Code keeps its current sign-in in the Keychain. Allow Sidebit to read it in Settings → Connections."
        case .notSignedIn(let message), .unavailable(let message): return message
        case .rateLimited: return "Usage is temporarily rate limited. Try again later."
        }
    }
}

private final class NoUsageRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct UsageReader: Sendable {
    private let home: URL
    private let allowKeychain: Bool
    private let keychain: @Sendable (String) -> Data?
    private static let maximumBytes = 262_144
    public static let claudeKeychainService = "Claude Code-credentials"
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, allowKeychain: Bool = false,
                keychain: @escaping @Sendable (String) -> Data? = { UsageReader.readKeychain($0) }) {
        self.home = home; self.allowKeychain = allowKeychain; self.keychain = keychain
    }

    /// Reads Claude Code's own Keychain item the way Claude Code does: through `/usr/bin/security`, which the item
    /// already trusts. Claude Code rewrites the item on every token refresh, so an app-level "Always Allow" would
    /// not survive; this read needs no new prompt. Sidebit never writes the item.
    public static func readKeychain(_ service: String) -> Data? {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty, data.count <= maximumBytes else { return nil }
        return data
    }

    /// Picks a current access token. Claude Code on macOS refreshes the Keychain copy, so a stale file falls back to it.
    func credentials(_ provider: Provider, now: Date = Date()) throws -> (token: String, account: String?) {
        let claude = provider == .claude
        func parse(_ data: Data?) -> (String, [String: Any], Date?)? {
            guard let data, data.count <= Self.maximumBytes,
                  let auth = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fields = auth[claude ? "claudeAiOauth" : "tokens"] as? [String: Any],
                  let token = fields[claude ? "accessToken" : "access_token"] as? String,
                  !token.isEmpty, !token.contains("\n"), !token.contains("\r") else { return nil }
            let expiry = (fields["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
            return (token, fields, expiry)
        }
        let file = home.appendingPathComponent(claude ? ".claude/.credentials.json" : ".codex/auth.json")
        let fromFile = parse((try? FileHandle(forReadingFrom: file)).flatMap { handle in defer { try? handle.close() }; return try? handle.read(upToCount: Self.maximumBytes + 1) })
        func current(_ value: (String, [String: Any], Date?)?) -> Bool { value.map { $0.2.map { $0 > now.addingTimeInterval(60) } ?? true } ?? false }
        func result(_ value: (String, [String: Any], Date?)) -> (token: String, account: String?) {
            (value.0, (value.1["account_id"] as? String).flatMap { $0.contains("\n") || $0.contains("\r") ? nil : $0 })
        }
        if current(fromFile), let fromFile { return result(fromFile) }
        if claude {
            guard allowKeychain else { throw UsageFailure.needsKeychain }
            // Keep the Keychain token in memory until it expires instead of asking every five minutes.
            if let cached = KeychainTokenCache.shared.token(now: now) { return (cached, nil) }
            if let stored = parse(keychain(Self.claudeKeychainService)), current(stored) {
                KeychainTokenCache.shared.store(stored.0, until: stored.2 ?? now.addingTimeInterval(3600))
                return result(stored)
            }
            throw UsageFailure.notSignedIn("Claude Code's sign-in has expired. Open Claude Code once so it can refresh, then try again.")
        }
        guard let fromFile else { throw UsageFailure.notSignedIn("No supported CLI sign-in was found. Sign in again with Codex.") }
        return result(fromFile)
    }

    public func fetch(_ provider: Provider) async throws -> UsageSnapshot {
        do {
            let claude = provider == .claude
            let url = URL(string: claude ? "https://api.anthropic.com/api/oauth/usage" : "https://chatgpt.com/backend-api/wham/usage")!
            // The first Keychain read shows a system prompt; never wait for it on the caller's actor.
            let reader = self
            let (token, account) = try await Task.detached(priority: .utility) { try reader.credentials(provider) }.value
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Sidebit/\(SidebitVersion.current)", forHTTPHeaderField: "User-Agent")
            if claude { request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta") }
            else if let account {
                request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
            }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 20
            config.httpCookieStorage = nil
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: config, delegate: NoUsageRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw Self.invalid() }
            try Self.checkStatus(response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
            guard response.expectedContentLength <= Self.maximumBytes else { throw Self.invalid() }
            var body = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard body.count < Self.maximumBytes else { throw Self.invalid() }
                body.append(byte)
            }
            return try claude ? Self.parseClaude(body) : Self.parseCodex(body)
        } catch let error as UsageFailure { throw error }
        catch is CancellationError { throw CancellationError() }
        catch { throw UsageFailure.unavailable("Usage could not be read. Check your connection and try again.") }
    }

    static func checkStatus(_ status: Int, retryAfter: String?, now: Date = Date()) throws {
        if status == 200 { return }
        if status == 401 { KeychainTokenCache.shared.clear() }
        if status == 401 || status == 403 { throw UsageFailure.notSignedIn("Usage access was denied. Sign in again with the provider's CLI.") }
        if status == 429 || (status == 503 && retryAfter != nil) {
            var delay = retryAfter.flatMap(Double.init)
            if delay == nil, let retryAfter {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                delay = formatter.date(from: retryAfter)?.timeIntervalSince(now)
            }
            let safeDelay = delay.flatMap { $0.isFinite ? $0 : nil } ?? 300
            throw UsageFailure.rateLimited(retryAfter: max(60, safeDelay))
        }
        throw UsageFailure.unavailable("The provider's usage service is unavailable (HTTP \(status)).")
    }
    private static func invalid() -> UsageFailure { .unavailable("The provider returned unsupported usage data.") }
    private static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= maximumBytes, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw invalid() }
        return value
    }
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    private static func percent(_ value: Any?) throws -> Double {
        guard let value = number(value), (0...100).contains(value) else { throw invalid() }
        return value
    }
    static func parseClaude(_ data: Data) throws -> UsageSnapshot {
        let root = try object(data)
        var windows: [UsageWindow] = []
        for (key, title, minutes) in [("five_hour", "5 hours", 300), ("seven_day", "7 days", 10080)] {
            guard let raw = root[key], !(raw is NSNull) else { continue }
            guard let item = raw as? [String: Any] else { throw invalid() }
            var date: Date?
            if let reset = item["resets_at"], !(reset is NSNull) {
                guard let string = reset as? String else { throw invalid() }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                date = formatter.date(from: string)
                if date == nil { formatter.formatOptions = [.withInternetDateTime]; date = formatter.date(from: string) }
                guard date != nil else { throw invalid() }
            }
            windows.append(UsageWindow(id: key, title: title, usedPercent: try percent(item["utilization"]), resetsAt: date, durationMinutes: minutes))
        }
        guard !windows.isEmpty else { throw invalid() }
        return UsageSnapshot(provider: .claude, windows: windows, source: "Claude account usage")
    }
    static func parseCodex(_ data: Data) throws -> UsageSnapshot {
        let root = try object(data)
        guard let limits = root["rate_limit"] as? [String: Any] else { throw invalid() }
        var windows: [UsageWindow] = []
        for key in ["primary_window", "secondary_window"] {
            guard let raw = limits[key], !(raw is NSNull) else { continue }
            guard let item = raw as? [String: Any], let seconds = number(item["limit_window_seconds"]), seconds >= 60, seconds <= 31_536_000 else { throw invalid() }
            let minutes = Int(seconds / 60)
            let title = minutes % 1440 == 0 ? "\(minutes / 1440) days" : minutes % 60 == 0 ? "\(minutes / 60) hours" : "\(minutes) minutes"
            var reset: Date?
            if let rawReset = item["reset_at"], !(rawReset is NSNull) {
                guard let epoch = number(rawReset), epoch > 0, epoch < 253_402_300_800 else { throw invalid() }
                reset = Date(timeIntervalSince1970: epoch)
            }
            windows.append(UsageWindow(id: key, title: title, usedPercent: try percent(item["used_percent"]), resetsAt: reset, durationMinutes: minutes))
        }
        guard !windows.isEmpty else { throw invalid() }
        let plan = (root["plan_type"] as? String).flatMap { $0.count <= 40 && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" } ? $0 : nil }
        return UsageSnapshot(provider: .codex, windows: windows, source: "Codex account usage", plan: plan)
    }
}

public enum SidebitVersion { public static let current = "0.7.0-beta.2" }

/// Last known allowance per provider, so a relaunch or a failed refresh never shows an empty card.
public struct UsageStore: Sendable {
    public let directory: URL
    public init(directory: URL = StoragePaths.directory("usage")) { self.directory = directory }
    private func file(_ provider: Provider) -> URL { directory.appendingPathComponent(provider.rawValue + ".json") }
    public func load(_ provider: Provider) -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: file(provider)), data.count <= 65_536 else { return nil }
        return try? JSONDecoder.journal.decode(UsageSnapshot.self, from: data)
    }
    public func save(_ snapshot: UsageSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let current = load(snapshot.provider), current.fetchedAt > snapshot.fetchedAt { return }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let url = file(snapshot.provider)
        try encoder.encode(snapshot).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// The last Keychain token, held in memory only, until one minute before it expires.
final class KeychainTokenCache: @unchecked Sendable {
    static let shared = KeychainTokenCache()
    private let lock = NSLock()
    private var value: (token: String, until: Date)?
    func token(now: Date) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let value, value.until > now.addingTimeInterval(60) else { return nil }
        return value.token
    }
    func store(_ token: String, until: Date) { lock.lock(); value = (token, until); lock.unlock() }
    func clear() { lock.lock(); value = nil; lock.unlock() }
}
