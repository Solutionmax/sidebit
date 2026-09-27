import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
// Bit's working poster: the same character people see on their desktop.
let pet = NSImage(contentsOf: root.appendingPathComponent("Sources/Snipkin/Resources/BitMovies/working.png"))!
let directory = root.appendingPathComponent(".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = base * scale
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor(srgbRed: 0.99, green: 0.86, blue: 0.72, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: Double(size) * 0.04, dy: Double(size) * 0.04), xRadius: Double(size) * 0.2, yRadius: Double(size) * 0.2).fill()
        pet.draw(in: CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: Double(size) * 0.02, dy: Double(size) * 0.02))
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
    }
}
