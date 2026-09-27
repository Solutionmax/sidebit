import Foundation
import CryptoKit

/// A newer release, found through the GitHub Releases API.
public struct UpdateInfo: Equatable, Sendable {
    public let version: String
    public let notes: String
    public let archive: URL
    public let signature: URL
    public let page: URL?
}

public enum UpdateFailure: Error, LocalizedError, Equatable {
    case notConfigured, unavailable, badSignature, invalidArchive, notWritable
    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Updates are not configured for this build."
        case .unavailable: return "Could not reach the update service. Try again later."
        case .badSignature: return "The download did not pass the signature check and was discarded."
        case .invalidArchive: return "The download did not contain a valid Sidebit update."
        case .notWritable: return "Sidebit cannot replace itself here. Move it to Applications and try again."
        }
    }
}

/// Signed over-the-air updates. Only archives signed by the release key are installed; nothing else is trusted.
public struct Updater: Sendable {
    public let feed: URL
    public let publicKey: Curve25519.Signing.PublicKey
    public let currentVersion: String
    /// Plain loopback downloads are only for a local test feed set through `SIDEBIT_UPDATE_FEED`.
    public var isTestFeed = false

    public init?(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let key = bundle.object(forInfoDictionaryKey: "SidebitUpdatePublicKey") as? String,
              let raw = Data(base64Encoded: key), let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return nil }
        let repository = bundle.object(forInfoDictionaryKey: "SidebitUpdateRepository") as? String ?? ""
        let feed = environment["SIDEBIT_UPDATE_FEED"].flatMap(URL.init(string:))
            ?? URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
        guard let feed, !repository.isEmpty || environment["SIDEBIT_UPDATE_FEED"] != nil else { return nil }
        self.init(feed: feed, publicKey: publicKey, currentVersion: SidebitVersion.current)
        isTestFeed = environment["SIDEBIT_UPDATE_FEED"] != nil
    }

    public init(feed: URL, publicKey: Curve25519.Signing.PublicKey, currentVersion: String) {
        self.feed = feed; self.publicKey = publicKey; self.currentVersion = currentVersion
    }

    /// Numeric dotted comparison; "0.10.0" is newer than "0.9.9". A leading "v" is ignored.
    /// A release is newer than its own prereleases: "0.7.0" beats "0.7.0-beta.2", which beats "0.7.0-beta.1".
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        func split(_ value: String) -> ([Int], [Int]?) {
            let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let pieces = trimmed.split(separator: "-", maxSplits: 1)
            let numbers = pieces.first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
            let pre = pieces.count > 1 ? pieces[1].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) } : nil
            return (numbers, pre)
        }
        func compare(_ a: [Int], _ b: [Int]) -> Int {
            for index in 0..<max(a.count, b.count) {
                let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
                if x != y { return x > y ? 1 : -1 }
            }
            return 0
        }
        let (a, preA) = split(candidate), (b, preB) = split(current)
        let base = compare(a, b)
        if base != 0 { return base > 0 }
        switch (preA, preB) {
        case (nil, nil): return false
        case (nil, .some): return true
        case (.some, nil): return false
        case let (.some(x), .some(y)): return compare(x, y) > 0
        }
    }

    /// Reads a GitHub "latest release" response. Drafts, prereleases and releases without a signed archive are ignored.
    public static func parse(_ data: Data, allowLoopback: Bool = false) -> UpdateInfo? {
        guard data.count <= 1_048_576, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["draft"] as? Bool != true, root["prerelease"] as? Bool != true,
              let tag = root["tag_name"] as? String, tag.count <= 40, let assets = root["assets"] as? [[String: Any]] else { return nil }
        func asset(_ suffix: String) -> URL? {
            assets.lazy.compactMap { item -> URL? in
                guard let name = item["name"] as? String, name.hasPrefix("Sidebit-"), name.hasSuffix(suffix),
                      let link = (item["browser_download_url"] as? String).flatMap(URL.init(string:)),
                      link.scheme == "https" || (allowLoopback && link.scheme == "http" && ["127.0.0.1", "localhost"].contains(link.host ?? "")) else { return nil }
                return link
            }.first
        }
        guard let archive = asset("-arm64.zip"), let signature = asset("-arm64.zip.sig") else { return nil }
        let notes = String((root["body"] as? String ?? "").prefix(4000))
        return UpdateInfo(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), notes: notes, archive: archive,
                          signature: signature, page: (root["html_url"] as? String).flatMap(URL.init(string:)))
    }

    public static func verify(_ archive: Data, signature: Data, key: Curve25519.Signing.PublicKey) -> Bool {
        let text = String(data: signature, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let raw = Data(base64Encoded: text), raw.count == 64 else { return false }
        return key.isValidSignature(raw, for: archive)
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        config.httpAdditionalHeaders = ["User-Agent": "Sidebit/\(currentVersion)", "Accept": "application/vnd.github+json"]
        return URLSession(configuration: config)
    }

    /// Returns a newer release, or nil when this build is current.
    public func check() async throws -> UpdateInfo? {
        let session = session()
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(from: feed), (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateFailure.unavailable }
        guard let info = Self.parse(data, allowLoopback: isTestFeed) else { return nil }
        return Self.isNewer(info.version, than: currentVersion) ? info : nil
    }

    /// Downloads and verifies the archive, then unpacks it. Returns the verified app bundle, ready to install.
    public func prepare(_ info: UpdateInfo, bundleIdentifier: String) async throws -> URL {
        let session = session()
        defer { session.finishTasksAndInvalidate() }
        guard let (archive, _) = try? await session.data(from: info.archive), archive.count < 200_000_000,
              let (signature, _) = try? await session.data(from: info.signature) else { throw UpdateFailure.unavailable }
        guard Self.verify(archive, signature: signature, key: publicKey) else { throw UpdateFailure.badSignature }
        return try Self.unpack(archive, bundleIdentifier: bundleIdentifier, newerThan: currentVersion)
    }

    static func unpack(_ archive: Data, bundleIdentifier: String, newerThan current: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sidebit-update-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let zip = folder.appendingPathComponent("update.zip")
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: folder) } }
        try archive.write(to: zip)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.appendingPathComponent("app").path]) else { throw UpdateFailure.invalidArchive }
        let app = folder.appendingPathComponent("app/Sidebit.app")
        guard let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              plist["CFBundleIdentifier"] as? String == bundleIdentifier,
              let version = plist["CFBundleShortVersionString"] as? String, isNewer(version, than: current),
              run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) else { throw UpdateFailure.invalidArchive }
        try? FileManager.default.removeItem(at: zip)
        succeeded = true
        return app
    }

    /// Replaces `target` with `update` after `pid` exits, restores the old copy on failure, then relaunches.
    public static func scheduleInstall(update: URL, replacing target: URL, pid: Int32) throws {
        let parent = target.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent), FileManager.default.isWritableFile(atPath: target.path) else { throw UpdateFailure.notWritable }
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let old = target.path + ".sidebit-old", lock = target.path + ".sidebit-installing"
        // One installer at a time; the original is only removed once its backup exists.
        let script = """
        mkdir \(quote(lock)) 2>/dev/null || exit 0
        trap 'rmdir \(quote(lock))' EXIT
        n=0; while kill -0 \(pid) 2>/dev/null; do n=$((n+1)); [ $n -gt 600 ] && exit 0; sleep 0.2; done
        rm -rf \(quote(old))
        if mv \(quote(target.path)) \(quote(old)); then
          if /usr/bin/ditto \(quote(update.path)) \(quote(target.path)); then rm -rf \(quote(old)); else rm -rf \(quote(target.path)); mv \(quote(old)) \(quote(target.path)); fi
        fi
        rm -rf \(quote(update.deletingLastPathComponent().deletingLastPathComponent().path))
        /usr/bin/open \(quote(target.path))
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
    }

    @discardableResult static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
