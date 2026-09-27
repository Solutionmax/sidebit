import AppKit
import ApplicationServices
import SnipkinCore

/// Reads allowlisted desktop button labels only. No browser, message fields, window titles or values.
@MainActor final class DesktopMonitor {
    struct App: Sendable {
        let bundle: String
        let title: String
        let provider: Provider
        let pid: Int32
        let path: String
        let hidden: Bool
    }
    struct Observation: Sendable {
        let app: App
        var activity: Activity = .unknown
    }
    static let supported: [(String, String, Provider)] = [
        ("com.anthropic.claudefordesktop", "Claude", .claude),
        ("com.openai.codex", "Codex", .codex)
    ]
    private let queue = DispatchQueue(label: "net.solutionmax.snipkin.desktop", qos: .utility)
    private var busy = false
    private var nextPoll = Date.distantPast
    private var generation = 0
    private var wasEnabled = false
    var receive: (([Session], Bool) -> Void)?

    func refresh(enabled: Bool) {
        guard enabled else {
            if wasEnabled {
                generation += 1; receive?([], AXIsProcessTrusted())
            }
            wasEnabled = false
            return
        }
        wasEnabled = true
        guard !busy, Date() >= nextPoll else { return }
        nextPoll = Date().addingTimeInterval(2)
        let trusted = AXIsProcessTrusted()
        let apps = NSWorkspace.shared.runningApplications.compactMap { running -> App? in
            guard let match = Self.supported.first(where: { $0.0 == running.bundleIdentifier }), let url = running.bundleURL else { return nil }
            return App(bundle: match.0, title: match.1, provider: match.2, pid: running.processIdentifier, path: url.path, hidden: running.isHidden)
        }
        busy = true
        let token = generation
        queue.async { [weak self] in
            let values = apps.map { trusted && !$0.hidden ? Self.observe($0) : Observation(app: $0) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy = false
                guard self.wasEnabled, token == self.generation else { return }
                let now = Date()
                let sessions = values.map { value -> Session in
                    let state = value.activity
                    let detail = !trusted ? "Accessibility permission required" : state == .unknown ? "App open · status unavailable" : "Observed desktop controls · experimental"
                    return Session(sessionID: "desktop:\(value.app.bundle)", provider: value.app.provider,
                                   cwd: value.app.title + " Desktop", activity: state, detail: detail,
                                   updatedAt: now, pid: value.app.pid, appBundlePath: value.app.path)
                }
                self.receive?(sessions, trusted)
            }
        }
    }

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    nonisolated private static func attribute(_ element: AXUIElement, _ name: String, failed: inout Bool) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard error == .success else {
            if error != .noValue && error != .attributeUnsupported { failed = true }
            return nil
        }
        return value
    }

    nonisolated private static func observe(_ app: App) -> Observation {
        var result = Observation(app: app)
        var failed = false
        let root = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(root, 0.08)
        // Electron apps may expose only their shell until a screen-reader client enables AX.
        _ = AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let rawWindow = attribute(root, kAXFocusedWindowAttribute, failed: &failed), CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { return result }
        let window = rawWindow as! AXUIElement
        guard attribute(window, kAXMinimizedAttribute, failed: &failed) as? Bool != true else { return result }
        let deadline = Date().addingTimeInterval(0.3)
        var stack: [(AXUIElement, Int)] = [(window, 0)]
        var visited = Set<CFHashCode>()
        var labels = Set<String>()
        var enabledLabels = Set<String>()
        var complete = true
        while !stack.isEmpty {
            guard visited.count < 1200, Date() < deadline else { complete = false; break }
            let (element, depth) = stack.removeLast()
            guard visited.insert(CFHash(element)).inserted else { continue }
            guard depth < 64 else { complete = false; continue }
            guard let role = attribute(element, kAXRoleAttribute, failed: &failed) as? String else { complete = false; continue }
            if role == kAXButtonRole {
                guard let enabled = attribute(element, kAXEnabledAttribute, failed: &failed) as? Bool else { complete = false; continue }
                // A disabled send button still identifies an idle composer.
                for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
                    if let text = attribute(element, name, failed: &failed) as? String, text.count < 70 {
                        let label = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        labels.insert(label)
                        if enabled { enabledLabels.insert(label) }
                    }
                }
            }
            // Never read editable content, static text, transcript values or window titles.
            if role == kAXTextAreaRole || role == kAXTextFieldRole || role == kAXStaticTextRole { continue }
            if let children = attribute(element, kAXChildrenAttribute, failed: &failed) as? [AXUIElement] {
                if children.count > 1200 { complete = false }
                stack.append(contentsOf: children.prefix(1200).map { ($0, depth + 1) })
            }
        }
        // Do not discard directly observed work/approval controls because unrelated nodes fail.
        // Idle still requires a complete successful scan.
        result.activity = DesktopActivity.fromControls(labels: labels, enabled: enabledLabels, complete: complete && stack.isEmpty && !failed)
        return result
    }
}
