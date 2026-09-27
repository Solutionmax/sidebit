import AppKit
import SwiftUI
import SnipkinCore

/// Assets are decoded once. Posters come from the films; the illustrated sheet is the playback fallback.
enum PetImages {
    static let scenes: [NSImage] = {
        guard let atlas = atlas(named: "pixel-scenes") else { return [] }
        let poses = (0..<6).compactMap { cell(atlas, columns: 3, rows: 2, index: $0) }
        return poses.count == 6 ? poses : []
    }()

    static let moviePosters: [String: NSImage] = {
        Dictionary(uniqueKeysWithValues: ["working", "thinking", "waiting", "done", "idle", "coffee", "unknown"].compactMap { name -> (String, NSImage)? in
            guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources/BitMovies"),
                  let image = NSImage(contentsOf: url) else { return nil }
            return (name, image)
        })
    }()

    private static func atlas(named name: String) -> CGImage? {
        let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources")
            ?? Bundle.module.url(forResource: name, withExtension: "png")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func cell(_ atlas: CGImage, columns: Int, rows: Int, index: Int) -> NSImage? {
        let width = atlas.width / columns, height = atlas.height / rows
        let rect = CGRect(x: (index % columns) * width, y: (index / columns) * height, width: width, height: height)
        guard let crop = atlas.cropping(to: rect) else { return nil }
        return NSImage(cgImage: crop, size: NSSize(width: width, height: height))
    }
}

struct PetView: View {
    var activity: Activity = .idle
    var size: CGFloat = 130
    var reducedMotion = false
    var decorations = true
    var gag = false
    var showQuip = false
    var quip = ""
    var quipContext: String?
    var urgentQuip = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var sceneStarted = Date()
    @State private var gagStarted = Date()
    @State private var failedMovies: Set<String> = []

    private var frozen: Bool { reducedMotion || systemReduceMotion || !decorations }
    private var scene: CharacterScene { CharacterScene(activity: activity, gag: gag && activity != .waiting && activity != .unknown) }

    private var movieScene: String { scene.gag ? "coffee" : activity.rawValue }
    private var movieKey: String { movieScene }
    private var movieURL: URL? {
        guard !frozen, !failedMovies.contains(movieKey) else { return nil }
        return BitMovieView.url(for: movieScene)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: movieURL != nil ? 1 : (activity == .idle ? 1.0 / 12 : 1.0 / 24), paused: frozen)) { context in
            let time = frozen ? 0 : max(0, context.date.timeIntervalSince(scene.gag ? gagStarted : sceneStarted))
            let motion = scene.motion(at: time, frozen: frozen)
            ZStack {
                if let url = movieURL {
                    let name = movieScene
                    let key = movieKey
                    BitMovieView(url: url, loops: name != "coffee" && name != "done") {
                        failedMovies.insert(key)
                    }
                    .frame(width: size, height: size)
                    .scaleEffect(Self.sceneScale[name] ?? 1, anchor: Self.feet)
                } else {
                    Ellipse().fill(.black.opacity(0.12))
                        .frame(width: size * 0.46, height: size * 0.045)
                        .blur(radius: 3).scaleEffect(x: 1 + motion.y, y: 1)
                        .offset(y: size * 0.40)
                    Group {
                        if let image = poseImage {
                            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                                .scaleEffect(Self.sceneScale[movieScene] ?? 1, anchor: Self.feet)
                        } else {
                            Image(systemName: "sparkles").resizable().scaledToFit()
                                .foregroundStyle(.orange).padding(size * 0.25)
                        }
                    }
                    .frame(width: size, height: size)
                    .scaleEffect(x: motion.scaleX, y: motion.scaleY, anchor: .bottom)
                    .rotationEffect(.degrees(motion.angle), anchor: .bottom)
                    .offset(x: motion.x * size, y: motion.y * size)
                    .id(decorations ? scene.index : -1)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))

                    if decorations {
                        SceneAccents(scene: scene, time: time, frozen: frozen)
                            .frame(width: size, height: size)
                    }
                }
                if !quip.isEmpty && decorations && (urgentQuip || (showQuip && (frozen || scene.showsQuip(at: time)))) {
                    SpeechBubble(text: quip, context: quipContext, fontSize: max(11.5, min(13.5, size * 0.07)))
                        .frame(maxWidth: min(size + 70, 220))
                        .offset(y: -size * 0.37)
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                        .id(quip)
                }
            }
            .frame(width: size + 30, height: size + 30)
        }
        .animation(frozen ? nil : .easeInOut(duration: 0.3), value: scene.index)
        .animation(frozen ? nil : .spring(response: 0.35, dampingFraction: 0.6), value: quip)
        .onChange(of: activity) { _, _ in sceneStarted = Date() }
        .onChange(of: scene.gag) { _, active in if active { gagStarted = Date() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Bit.name), \(scene.gag ? "\(activity.title), coffee break" : activity.title)")
    }

    /// The films frame Bit at slightly different sizes. Measured from each poster's visible height
    /// (working is the reference), so Bit keeps one size across scenes. Feet stay where they are.
    static let sceneScale: [String: CGFloat] = ["done": 1.15, "waiting": 1.13, "unknown": 1.03, "idle": 0.96]
    static let feet = UnitPoint(x: 0.5, y: 0.92)

    private var poseImage: NSImage? {
        if decorations, let poster = PetImages.moviePosters[movieScene] { return poster }
        if decorations, PetImages.scenes.indices.contains(scene.index) { return PetImages.scenes[scene.index] }
        return PetImages.moviePosters["working"] ?? PetImages.scenes.first
    }
}

/// Obsidian speech: a dark glass card, the line as a serif quote, and a small monospaced caption.
struct SpeechBubble: View {
    let text: String
    var context: String?
    var fontSize: CGFloat = 12
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // One typeface, readable at every companion size.
            Text(text).font(.geist(fontSize, .medium)).foregroundStyle(ink).lineLimit(2)
            if let context, !context.isEmpty {
                Text(context).font(.geist(max(10, fontSize - 1.5))).foregroundStyle(muted).lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color(.sRGB, red: 0.086, green: 0.086, blue: 0.094, opacity: 0.94)))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
        .environment(\.colorScheme, .dark)
    }
}
