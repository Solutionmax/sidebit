import AppKit
import AVFoundation
import SwiftUI
import SnipkinCore

/// `--export-media <dir>`: renders README media (animation frames, medal case, menu bar) with example data, then quits.
/// Development only; it reads no user data.
@MainActor enum DevExport {
    static func run(to directory: URL, model: AppModel) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        func write(_ image: NSImage?, _ name: String) {
            guard let tiff = image?.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            let url = directory.appendingPathComponent(name)
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? png.write(to: url)
        }
        func render<V: View>(_ view: V, scale: CGFloat = 2) -> NSImage? {
            let renderer = ImageRenderer(content: view); renderer.scale = scale; return renderer.nsImage
        }
        // Medal reveal, 20 fps for 3 seconds.
        for frame in 0..<60 {
            write(render(MomentToast(moment: .juggler, count: 7, time: Double(frame) / 20, scale: 0.8), scale: 1.5), String(format: "reveal/%03d.png", frame))
        }
        write(render(MedalShowcase().padding(40).background(Color(.sRGB, red: 0.035, green: 0.035, blue: 0.04, opacity: 1))), "medals.png")
        write(render(MenuBarStrip()), "menubar.png")
        for (pose, line, context) in [("working", "sudo make me a sandwich.", "Website · Running command"), ("waiting", "A little yes would go a long way.", "API · Permission needed"),
                                      ("done", "I did a thing!", "Docs · Response complete")] {
            write(render(BubbleScene(pose: pose, line: line, context: context)), "bubble-\(pose).png")
        }
        // Bit's films, 12 fps for 4 seconds each, on the dark stage.
        for scene in ["working", "thinking", "waiting", "done", "idle", "coffee"] {
            guard let url = BitMovieView.url(for: scene) else { continue }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 360, height: 360)
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            for frame in 0..<48 {
                guard let cg = try? generator.copyCGImage(at: CMTime(seconds: Double(frame) / 12, preferredTimescale: 600), actualTime: nil) else { continue }
                let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                write(image, String(format: "film-\(scene)/%03d.png", frame))
            }
        }
        NSApp.terminate(nil)
    }
}

/// All medals, unlocked, grouped by metal.
private struct MedalShowcase: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(Rarity.allCases.reversed(), id: \.self) { rarity in
                VStack(alignment: .leading, spacing: 14) {
                    Kicker(text: rarity.title, trailing: "\(Moment.allCases.filter { $0.rarity == rarity }.count) medals")
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(118), spacing: 10), count: 7), alignment: .leading, spacing: 18) {
                        ForEach(Moment.allCases.filter { $0.rarity == rarity }, id: \.self) { moment in
                            VStack(spacing: 8) {
                                Medal(moment: moment, size: 72)
                                Text(moment.title).font(.geist(12, .medium)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
                            }.frame(width: 118)
                        }
                    }
                }
            }
        }.frame(width: 900, alignment: .leading).environment(\.colorScheme, .dark)
    }
}

/// A dark menu bar showing each state of the bubble icon.
private struct MenuBarStrip: View {
    var body: some View {
        HStack(spacing: 18) {
            ForEach([(BitGlyph.Eyes.open, "Working", ""), (.closed, "Idle", ""), (.wide, "Needs you", "Website needs you"), (.star, "Done", "")], id: \.1) { eyes, label, text in
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(nsImage: BitGlyph.image(eyes, tint: eyes == .wide ? .systemOrange : .white)).resizable().frame(width: 18, height: 18)
                        if !text.isEmpty { Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(nsColor: .systemOrange)) }
                    }
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Color(.sRGB, red: 0.16, green: 0.16, blue: 0.18, opacity: 1), in: RoundedRectangle(cornerRadius: 7))
                    Text(label.uppercased()).font(.mono(10, .medium)).tracking(1.2).foregroundStyle(muted)
                }
            }
        }.padding(26).background(Color(.sRGB, red: 0.035, green: 0.035, blue: 0.04, opacity: 1))
    }
}

/// Bit with a speech bubble, as it sits on the desktop.
private struct BubbleScene: View {
    let pose: String
    let line: String
    let context: String
    var body: some View {
        ZStack {
            if let image = PetImages.moviePosters[pose] {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 190, height: 190)
                    .scaleEffect(PetView.sceneScale[pose] ?? 1, anchor: PetView.feet).offset(y: 20)
            }
            SpeechBubble(text: line, context: context, fontSize: 13).frame(maxWidth: 220).offset(y: -78)
        }.frame(width: 260, height: 270).environment(\.colorScheme, .dark)
    }
}
