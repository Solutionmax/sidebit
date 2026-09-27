# Bit: a little personality

Bit is diligent, slightly stubborn, and disproportionately proud of small wins. The orange voxel character and its graphite laptop stay recognizable across seven original scenes.

| Scene | Personality | Playback |
| --- | --- | --- |
| Working | Concentrated typing and little glances | 9.5-second loop |
| Thinking | Consulting a tiny rubber duck like a senior engineer | 9.5-second loop |
| Waiting | A patient, hopeful wave | 9.5-second loop |
| Done | Proud trophy lift, wink, and satisfied nod | 10 seconds, then hold |
| Idle | Dozing on a closed laptop, rubbing a sleepy face | 9.5-second loop |
| Coffee | Taking three espresso mugs far too seriously | 10 seconds, then hold |
| Unknown | Inspecting a loose cable, honestly puzzled | 9.5-second loop |

Waiting takes priority over coffee. One-shots restart after leaving and re-entering their scene, not on every model refresh. Coffee remains an optional 18-second break, with the final pose held for the remainder. Movies are silent; the existing optional event sounds remain separate.

## Generation and provenance

Created with fal.ai Nano Banana Pro Edit reference images and Kling 2.5 Turbo Pro image-to-video. The approved working study was reused. Six other states were generated from that character reference. Thinking, done, and coffee received targeted video retakes; thinking also received a revised reference. Rejected takes had floating props or excessive shape changes.

Provider-reported cost for this batch: **$7.35** (seven new reference images × $0.15, nine video generations × $0.70). The earlier $0.85 working study is separate. Requests and costs are preserved in [bit-movie-prompts.json](bit-movie-prompts.json). Local raw videos, reference images and rejected takes remain under `output/bit-personality` and `output/fal-bit`; these large development intermediates are not shipped or tracked in Git.

Final movies and corresponding transparent PNG posters are committed under `Sources/Sidebit/Resources/BitMovies`. These are original AI-generated assets, not copied from Codenotch, Claude Status Bar, or provider logos. Generation services are used only during asset production. The installed app does not call fal.ai, download animation files, or require a generation account.

## Native pipeline

`scripts/prepare-bit-movie.py` keys the green background, removes green spill, calculates one fixed crop from every frame's alpha bounds, and places the character on a 512×512 transparent canvas. Loops blend their last half-second into the opening half-second. FFmpeg 7.0.2 or newer is required for Apple-compatible ProRes alpha; Pillow reads alpha bounding boxes only.

`scripts/encode-alpha.swift` exports native HEVC with alpha and verifies real decoded transparency, dimensions, duration and codec. See [encoding details](bit-alpha-encoding.md). Each scene is approximately 3 MB. The native player holds one queue, uses AVPlayerLooper for looping scenes, pauses hidden windows, disposes old playback on a scene change, and falls back to illustration when playback fails. Reduced Motion uses matching posters without starting video playback.

## Honest limits

These are generated character films, not a rigged 3D character. Small changes in faces, pincers, and props remain visible when enlarged. Loop boundaries are softened crossfades, not perfectly matched procedural motion; a brief blend can be visible. The fixed desktop size makes the acting readable, but source footage should be reviewed again before using these assets at large promotional sizes.

The development gallery repeats all seven scenes for comparison, including the two one-shots. In the app, done and coffee play once. Native view-cache screenshots omit AVPlayerLayer content, so video QA uses actual window captures and native playback checks.
