# Bit native alpha movies

Run on macOS with Apple's Swift toolchain; no package dependencies:

```sh
swift -suppress-warnings scripts/encode-alpha.swift input-prores.mov bit-working.mov
```

The tool exports with `AVAssetExportPresetHEVCHighestQualityWithAlpha`, checks HEVC format and alpha metadata, compares duration, then decodes the first and middle frames into BGRA pixels with `AVAssetReader`. Both frames must contain fully transparent and visible pixels. One JSON line reports duration, dimensions, alpha range and transparent/opaque/partial pixel counts. Failures exit nonzero and remove the newly created output. Existing files are never overwritten. The macOS 14 compatible APIs emit deprecation warnings with newer SDKs; `-suppress-warnings` keeps batch logs readable.

## Prepare intermediates

Use FFmpeg **7.0.2 or newer** for `prores_ks` intermediates. The system's FFmpeg 6.1 produced ProRes with an invalid alpha bitstream version: FFmpeg could decode its alpha, but Apple's decoder returned fully opaque pixels. Export metadata alone still claimed alpha. FFmpeg fixed the [bitstream version](https://ffmpeg.org/pipermail/ffmpeg-cvslog/2024-January/140455.html) and [reserved alpha bits](https://ffmpeg.org/pipermail/ffmpeg-cvslog/2024-January/140456.html) in January 2024. QuickTime Animation (`qtrle`) was rejected by the tested native exporter.

Example for square input; adjust the key to the reviewed matte:

```sh
ffmpeg -i bit-working-raw.mp4 \
  -vf 'scale=512:512,format=rgba,colorkey=0x00FF00:0.18:0.10,despill=type=green:mix=0.5' \
  -c:v prores_ks -profile:v 4 -pix_fmt yuva444p10le -an input-prores.mov
```

For a VP9 WebM alpha input, select `-c:v libvpx-vp9` **before** `-i`; the default decoder can discard alpha.

Apple documents the export preset and native alpha playback/decoding in [HEVC Video with Alpha](https://developer.apple.com/videos/play/wwdc2019/506/). Linux FFmpeg decoding of final HEVC is not sufficient to validate Apple's auxiliary alpha layer.
