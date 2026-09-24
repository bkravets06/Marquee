# Marquee — notes for coding sessions

## Picking up in a new session

Read `docs/HANDOFF.md` first. It records what is finished, what still needs
to be verified on a real simulator or device, the debug launch arguments,
and the open follow-ups.

## What this is

Marquee is a native iOS app (SwiftUI + SwiftData, iOS 18+, Swift 5 language mode) that tracks the shows and movies a person is watching. It uses TMDB as its catalog API and schedules local notifications for new episodes. No server, no accounts, no third-party dependencies.

## Layout

```
Marquee.xcodeproj/      Xcode project (synchronized folders), scheme "Marquee"
Marquee/                iOS app target: Support/, Models/, Services/, Components/, Features/<Screen>/
MarqueeTests/           XCTest target for the app (LibraryStore, MediaItem, notification planning)
MarqueeKit/             Local Swift package: Domain/ + TMDB/ (pure Foundation, builds on Linux)
docs/ARCHITECTURE.md    The contract between modules (names, signatures, UI spec)
scripts/                check_syntax.py (tree-sitter parse check), generate_icon.py (app icon)
.github/workflows/      ci.yml (macOS runner)
```

## The spec is the contract

`docs/ARCHITECTURE.md` is normative. Type names, signatures, file locations and the UI spec there are what every module links against. Implement exactly those names. If you must deviate, update the spec in the same change and say so.

## Building and testing

On macOS:

```sh
swift test --package-path MarqueeKit
xcodebuild -project Marquee.xcodeproj -scheme Marquee \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  CODE_SIGNING_ALLOWED=NO build test
```

On Linux (no Swift toolchain or Xcode): nothing can be compiled. Before finishing, run

```sh
python3 scripts/check_syntax.py            # pip install tree-sitter tree-sitter-swift
python3 -c "import json; json.load(open('Marquee/Assets.xcassets/AppIcon.appiconset/Contents.json'))"
python3 -c "import plistlib; plistlib.load(open('Marquee/Info.plist','rb'))"
```

and re-read each changed Swift file as a reviewer looking for compile errors (imports, argument labels, optionals, access control, actor isolation). Prefer conservative, well-known APIs and explicit types.

## Conventions

- Swift 5 language mode, `SWIFT_STRICT_CONCURRENCY = minimal`, deployment target iOS 18.
- No third-party dependencies. No iOS 26-only APIs (no `glassEffect`, no iOS 26-only modifiers); Liquid Glass comes for free from system controls when built with Xcode 26.
- No UIKit/SwiftUI/SwiftData imports inside MarqueeKit; wrap `URLSession` usage in `#if canImport(FoundationNetworking)`.
- Every SwiftData mutation goes through `LibraryStore` (sets `updatedAt`, saves). Views never touch `ModelContext` directly.
- Every TMDB call goes through `AppEnvironment.client` (optional; UI must handle `nil`). All calls are `async`; never block the main thread.
- View models are `@MainActor @Observable final class`, owned with `@State`. Every screen has a `#Preview` using `PreviewData`.
- Style: `// MARK: -` sections, doc comments on shared API, `guard` early exits, no force unwraps outside tests and previews, one primary type per file, plain English string literals.
- Split large SwiftUI bodies into subviews and computed properties so the type checker stays fast.
- Do not commit or push unless asked. Never commit API tokens.

## CI

`.github/workflows/ci.yml` runs on every push, pull request and manual dispatch on a `macos-26` runner: it selects the newest Xcode 26, runs `swift test --package-path MarqueeKit`, picks an available iPhone simulator (preferring iPhone 17, then 16), runs `xcodebuild build test` for the Marquee scheme with code signing disabled, and uploads `xcodebuild.log` and `package-test.log` as artifacts. Concurrent runs on the same ref cancel each other.
