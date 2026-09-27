#!/usr/bin/env swift
import Foundation
import AVFoundation
import CoreVideo
import Darwin

// macOS-only. Input must already contain an alpha channel (for example ProRes 4444).
struct EncodeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func alphaSample(_ asset: AVAsset, track: AVAssetTrack, seconds: Double) throws -> [String: Any] {
    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = CMTimeRange(start: CMTime(seconds: seconds, preferredTimescale: 600), duration: .positiveInfinity)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    guard reader.canAdd(output) else { throw EncodeFailure("Cannot decode BGRA frames") }
    reader.add(output)
    guard reader.startReading(), let sample = output.copyNextSampleBuffer(),
          let pixels = CMSampleBufferGetImageBuffer(sample) else {
        throw reader.error ?? EncodeFailure("No decoded frame at \(seconds)s")
    }
    defer { reader.cancelReading() }
    guard CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA else {
        throw EncodeFailure("Decoder returned unexpected pixel format")
    }
    CVPixelBufferLockBaseAddress(pixels, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(pixels) else { throw EncodeFailure("Missing pixels") }
    let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
    let stride = CVPixelBufferGetBytesPerRow(pixels)
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    var minimum = 255, maximum = 0, transparent = 0, opaque = 0, partial = 0
    for y in 0..<height {
        for x in 0..<width {
            let alpha = Int(bytes[y * stride + x * 4 + 3])
            minimum = min(minimum, alpha); maximum = max(maximum, alpha)
            if alpha == 0 { transparent += 1 }
            else if alpha == 255 { opaque += 1 }
            else { partial += 1 }
        }
    }
    guard transparent > 0, opaque + partial > 0 else {
        throw EncodeFailure("Frame at \(seconds)s lacks both transparent and visible pixels (alpha \(minimum)...\(maximum))")
    }
    return ["seconds": seconds, "width": width, "height": height,
            "alphaMin": minimum, "alphaMax": maximum,
            "transparentPixels": transparent, "opaquePixels": opaque, "partialPixels": partial]
}

func run() async throws {
    guard CommandLine.arguments.count == 3 else {
        throw EncodeFailure("Usage: swift scripts/encode-alpha.swift input.mov output.mov")
    }
    let input = URL(fileURLWithPath: CommandLine.arguments[1])
    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    guard FileManager.default.fileExists(atPath: input.path) else { throw EncodeFailure("Input missing: \(input.path)") }
    guard !FileManager.default.fileExists(atPath: output.path) else { throw EncodeFailure("Output already exists: \(output.path)") }
    var verified = false
    defer { if !verified { try? FileManager.default.removeItem(at: output) } }
    let source = AVURLAsset(url: input)
    let sourceDuration = try await source.load(.duration).seconds
    guard sourceDuration.isFinite, sourceDuration > 0 else { throw EncodeFailure("Input has no duration") }
    guard let exporter = AVAssetExportSession(asset: source, presetName: AVAssetExportPresetHEVCHighestQualityWithAlpha) else {
        throw EncodeFailure("HEVC alpha export unavailable")
    }
    exporter.outputURL = output
    exporter.outputFileType = .mov
    await withCheckedContinuation { continuation in
        exporter.exportAsynchronously { continuation.resume() }
    }
    guard exporter.status == .completed else {
        throw exporter.error ?? EncodeFailure("Export failed with status \(exporter.status.rawValue)")
    }
    let encoded = AVURLAsset(url: output)
    let duration = try await encoded.load(.duration).seconds
    guard abs(duration - sourceDuration) < 0.1 else { throw EncodeFailure("Output duration differs from input") }
    guard let track = try await encoded.loadTracks(withMediaType: .video).first else { throw EncodeFailure("Missing output video") }
    let descriptions = try await track.load(.formatDescriptions)
    guard let format = descriptions.first, CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_HEVC else {
        throw EncodeFailure("Output is not HEVC")
    }
    let alphaMetadata = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_ContainsAlphaChannel)
    let containsAlpha = (alphaMetadata as? NSNumber)?.boolValue ?? false
    guard containsAlpha else { throw EncodeFailure("Output does not advertise an alpha channel") }
    let samples = try [0.0, duration / 2].map { try alphaSample(encoded, track: track, seconds: $0) }
    let report: [String: Any] = ["file": output.path, "codec": "HEVC", "duration": duration,
                               "containsAlphaMetadata": containsAlpha, "samples": samples]
    let json = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    verified = true
    print(String(decoding: json, as: UTF8.self))
}

Task {
    do { try await run(); exit(0) }
    catch { FileHandle.standardError.write(Data("encode-alpha: \(error)\n".utf8)); exit(1) }
}
dispatchMain()
