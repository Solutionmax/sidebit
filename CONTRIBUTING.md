# Contributing

Build on an Apple Silicon Mac with macOS 14+ and a Swift 6 toolchain (Xcode 16 or later).
Run `swift test`, `./scripts/build-app.sh`, and `python3 scripts/smoke-hooks.py dist/Sidebit.app` before submitting a change.

- Keep the app native and dependency-free. Use English for interface text and documentation.
- Preserve Reduce Motion behavior and distinguish live state from example data. Missing quota data must never become a zero.
- Waiting for input always takes priority over jokes, coffee breaks and celebrations.
- New quips go in `Sources/SnipkinCore/Quips.swift`. Keep them kind, short (44 characters or fewer) and about the work, never about the user.
- New medals go in `Sources/SnipkinCore/Moments.swift`: one `Info` line plus one rule in `Moment.earned`, and a test. They may only use counts and times, never content. Pick the metal honestly: obsidian is for things almost nobody gets.
- For animation changes, check every scene at the smallest supported size.

Never include credentials, real session files, private project paths, or conversation contents in issues, screenshots, fixtures, or logs. Usage tests use synthetic data; CI must not depend on a signed-in account.
