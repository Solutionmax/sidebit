import XCTest
import CryptoKit
@testable import SnipkinCore

final class UpdateTests: XCTestCase {
    func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testVersionOrdering() {
        XCTAssertTrue(Updater.isNewer("0.10.0", than: "0.9.9"))
        XCTAssertTrue(Updater.isNewer("v0.7.0", than: "0.6.0"))
        XCTAssertTrue(Updater.isNewer("1.0", than: "0.99.1"))
        XCTAssertFalse(Updater.isNewer("0.7.0", than: "0.7.0"))
        XCTAssertFalse(Updater.isNewer("0.6.9", than: "0.7.0"))
        XCTAssertFalse(Updater.isNewer("0.7.0-beta", than: "0.7.0"))
        XCTAssertTrue(Updater.isNewer("0.7.0", than: "0.7.0-beta.1"))
        XCTAssertTrue(Updater.isNewer("0.7.0-beta.2", than: "0.7.0-beta.1"))
        XCTAssertFalse(Updater.isNewer("0.7.0-beta.1", than: "0.7.0-beta.1"))
        XCTAssertTrue(Updater.isNewer("0.7.1-beta.1", than: "0.7.0"))
    }

    func testParsesOnlySignedStableReleases() {
        func release(draft: Bool = false, sig: Bool = true, scheme: String = "https") -> Data {
            var assets: [[String: Any]] = [["name": "Sidebit-0.7.0-arm64.zip", "browser_download_url": "\(scheme)://example.com/a.zip"]]
            if sig { assets.append(["name": "Sidebit-0.7.0-arm64.zip.sig", "browser_download_url": "https://example.com/a.zip.sig"]) }
            return try! JSONSerialization.data(withJSONObject: ["tag_name": "v0.7.0", "draft": draft, "body": "Notes", "assets": assets])
        }
        XCTAssertEqual(Updater.parse(release())?.version, "0.7.0")
        XCTAssertEqual(Updater.parse(release())?.notes, "Notes")
        XCTAssertNil(Updater.parse(release(draft: true)))
        XCTAssertNil(Updater.parse(release(sig: false)))
        XCTAssertNil(Updater.parse(release(scheme: "http")))
        let loopback = try! JSONSerialization.data(withJSONObject: ["tag_name": "v1", "assets": [
            ["name": "Sidebit-1-arm64.zip", "browser_download_url": "http://127.0.0.1:1/a"], ["name": "Sidebit-1-arm64.zip.sig", "browser_download_url": "http://127.0.0.1:1/b"]]])
        XCTAssertNil(Updater.parse(loopback), "Loopback only for an explicit test feed")
        XCTAssertNotNil(Updater.parse(loopback, allowLoopback: true))
        XCTAssertNil(Updater.parse(Data("nope".utf8)))
    }

    func testSignatureMustMatchTheReleaseKey() throws {
        let key = Curve25519.Signing.PrivateKey(), other = Curve25519.Signing.PrivateKey()
        let archive = Data("zip bytes".utf8)
        let good = Data(try key.signature(for: archive).base64EncodedString().utf8)
        XCTAssertTrue(Updater.verify(archive, signature: good, key: key.publicKey))
        XCTAssertFalse(Updater.verify(archive + Data([0]), signature: good, key: key.publicKey))
        XCTAssertFalse(Updater.verify(archive, signature: good, key: other.publicKey))
        XCTAssertFalse(Updater.verify(archive, signature: Data("garbage".utf8), key: key.publicKey))
    }

    /// Builds a tiny signed bundle, zips it, unpacks it through the updater and installs it over a fake app.
    func testUnpackAndInstallReplacesTheApp() throws {
        let root = try temporary()
        func makeApp(_ version: String, at url: URL) throws {
            try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            let plist: NSDictionary = ["CFBundleIdentifier": "test.sidebit", "CFBundleShortVersionString": version, "CFBundleExecutable": "Sidebit", "CFBundlePackageType": "APPL"]
            plist.write(to: url.appendingPathComponent("Contents/Info.plist"), atomically: true)
            try Data("#!/bin/sh\n".utf8).write(to: url.appendingPathComponent("Contents/MacOS/Sidebit"))
            XCTAssertTrue(Updater.run("/usr/bin/codesign", ["--force", "--sign", "-", url.path]))
        }
        let source = root.appendingPathComponent("build/Sidebit.app")
        try makeApp("9.0.0", at: source)
        let zip = root.appendingPathComponent("update.zip")
        XCTAssertTrue(Updater.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, zip.path]))
        let archive = try Data(contentsOf: zip)
        XCTAssertThrowsError(try Updater.unpack(archive, bundleIdentifier: "other.app", newerThan: "1.0"))
        XCTAssertThrowsError(try Updater.unpack(archive, bundleIdentifier: "test.sidebit", newerThan: "9.0.0"))
        let staged = try Updater.unpack(archive, bundleIdentifier: "test.sidebit", newerThan: "1.0")

        let target = root.appendingPathComponent("Applications/Sidebit.app")
        try makeApp("1.0", at: target)
        try Updater.scheduleInstall(update: staged, replacing: target, pid: 2_147_483_000)
        let deadline = Date().addingTimeInterval(10)
        var version: String?
        repeat {
            usleep(100_000)
            version = NSDictionary(contentsOf: target.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
        } while version != "9.0.0" && Date() < deadline
        XCTAssertEqual(version, "9.0.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path + ".sidebit-old"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().deletingLastPathComponent().path), "Staging is cleaned up")

        // A failing rename must leave the installed app untouched.
        let locked = root.appendingPathComponent("Locked")
        let kept = locked.appendingPathComponent("Sidebit.app")
        try makeApp("1.0", at: kept)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        XCTAssertThrowsError(try Updater.scheduleInstall(update: staged, replacing: kept, pid: 2_147_483_000))
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.appendingPathComponent("Contents/Info.plist").path))
        let before = try FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory()).filter { $0.hasPrefix("sidebit-update-") }.count
        _ = try? Updater.unpack(archive, bundleIdentifier: "other.app", newerThan: "1.0")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory()).filter { $0.hasPrefix("sidebit-update-") }.count, before, "Failed unpacks leave nothing behind")
    }

    func testMoreMomentsAndRarity() throws {
        XCTAssertEqual(Moment.allCases.count, 34)
        XCTAssertTrue(Moment.allCases.allSatisfy { $0.title.count <= 20 && $0.hint.count <= 28 && !$0.blurb.isEmpty })
        XCTAssertEqual(Set(Moment.allCases.map(\.rarity)), Set(Rarity.allCases))
        var day = DayJournal(day: "2028-02-29"); day.turns = 20; day.boops = 10
        let earned = Moment.earned(by: day, streak: 0)
        XCTAssertTrue(earned.contains(.leapCoder) && earned.contains(.flawless) && earned.contains(.boopEnthusiast))
        XCTAssertFalse(Moment.earned(by: DayJournal(day: "2026-01-01"), streak: 0).contains(.freshStart), "An empty day earns nothing")

        let journal = Journal(directory: try temporary())
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        let friday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 17))!
        let unlocked = try journal.record(event: "PreToolUse", tool: "Bash", provider: .claude, project: "p", now: friday, calendar: calendar)
        XCTAssertTrue(unlocked.contains(.fridayDeploy))
        for _ in 0..<10 { try journal.record(.boop, now: friday, calendar: calendar) }
        XCTAssertTrue(journal.moments().contains { $0.id == Moment.boopEnthusiast.rawValue })
        for _ in 0..<3 { try journal.record(event: "Stop", tool: nil, provider: .claude, project: "p", now: friday, calendar: calendar) }
        XCTAssertEqual(journal.lifetime().turns, 3)
        XCTAssertEqual(journal.lifetime().activeDays, 1)
    }
}
