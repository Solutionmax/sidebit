import AppKit
import SnipkinCore

if let code = HookRuntime.run() { exit(code) }

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: CompanionController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Fonts.register()
        if CommandLine.arguments.contains("--preview-dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if CommandLine.arguments.contains("--preview-light") { NSApp.appearance = NSAppearance(named: .aqua) }
        let model = AppModel()
        if let index = CommandLine.arguments.firstIndex(of: "--preview-state"), CommandLine.arguments.count > index + 1 {
            let state = CommandLine.arguments[index + 1]
            model.demo = true
            model.demoActivity = Activity(rawValue: state) ?? .working
            if state == "coffee" { model.playTinyBreak() }
        }
        controller = CompanionController(model: model)
        if let index = CommandLine.arguments.firstIndex(of: "--export-media"), CommandLine.arguments.count > index + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { DevExport.run(to: directory, model: model) }
        }
        // Renders today's card from real local data to a file, then quits. Used to share without clicking.
        if let index = CommandLine.arguments.firstIndex(of: "--export-today"), CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if let image = ShareCardExporter.render(ShareCardExporter.todayCard(model: model)), let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--show-status") || (model.demo && !CommandLine.arguments.contains("--show-hover")) { controller?.showStatus() }
        if CommandLine.arguments.contains("--show-hover") { controller?.showHover() }
        if ["--show-settings", "--show-connections", "--show-moments"].contains(where: CommandLine.arguments.contains) { controller?.openSettings() }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot-dir"), CommandLine.arguments.count > index + 1 {
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            var delay = 2.0
            if let delayIndex = CommandLine.arguments.firstIndex(of: "--snapshot-delay"), CommandLine.arguments.count > delayIndex + 1,
               let requested = Double(CommandLine.arguments[delayIndex + 1]), requested.isFinite {
                delay = min(60, max(0.2, requested))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.controller?.captureViews(to: url) }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.4) { [weak self] in self?.controller?.captureViews(to: url.appendingPathComponent("next-frame")) }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showStatus()
        return true
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { application.run() }
}
