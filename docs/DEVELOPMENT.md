# Developing Stackbar

## Stack

- Swift 6 with strict concurrency, SwiftUI, macOS 26 deployment target.
- [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) (TCA)
  for state and side effects.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `project.yml` is the source of truth; the
  `.xcodeproj` is generated.
- Swift Testing for unit tests, XCTest for UI tests.

## Quick start

Requirements: Xcode 27.2 and XcodeGen (`brew install xcodegen`).

```sh
xcodegen generate
open Stackbar.xcodeproj
```

Then press **⌘R**. On the first build Xcode asks you to trust the TCA macro packages: accept,
otherwise the build fails with macro validation errors.

Run `xcodegen generate` again whenever you add, move or delete a source file.

### Command line

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # if xcode-select points to CLT

xcodebuild -skipMacroValidation -project Stackbar.xcodeproj -scheme Stackbar \
  -destination 'platform=macOS,arch=arm64' build

# Unit tests only (fast)
xcodebuild -skipMacroValidation -project Stackbar.xcodeproj -scheme Stackbar \
  -destination 'platform=macOS,arch=arm64' -only-testing:StackbarTests test

# A single suite
... -only-testing:StackbarTests/CommandDetectorTests test
```

`-skipMacroValidation` is required for non-interactive builds of the pinned TCA macros. If you hit
odd link errors after switching branches, clean the build folder (**⇧⌘K**) or delete DerivedData.

## Project layout

| Folder | Content |
|---|---|
| `Stackbar/App` | Entry point (`MenuBarExtra`, Settings and log windows), root `AppFeature`, `AppTerminationCoordinator` (safe quit). |
| `Stackbar/Domain` | Pure, tested types: `Project`/`Service` and validation, `ProjectDraft` (editing model), `ProjectsDocument` (file format and migration), `CommandDetector`, `URLDetector`, `LogBuffer`, runtime status. |
| `Stackbar/Features` | TCA reducers: `ProjectsFeature` (launch/stop/delete/save), `PreferencesFeature`, `LogsFeature`. |
| `Stackbar/Services` | Side-effect clients: `ProjectProcessManager` actor, `RunningServiceRegistry` (crash recovery), `PortClient` (`lsof` port check), `LoginShell`, `ProjectRepository`, `LogStore`, AppKit/notification/login-item clients. |
| `Stackbar/Views` | SwiftUI views; shared look (status dot, hover and play/stop buttons, settings cards) in `Views/Components/StackbarStyle.swift`. |
| `StackbarProcessHost` | Tiny C helper: puts the command in its own process group, then `exec`s the shell, so a stop can terminate every child process. |
| `StackbarTests`, `StackbarUITests` | Unit and UI tests. |
| `docs` | Product requirements, technical architecture, release acceptance checklist. |

Key rules (details in [architecture-technique-stackbar.md](architecture-technique-stackbar.md)):

- `Process` objects and raw logs live in actors (`ProjectProcessManager`, `LogStore`), never in TCA
  state; lifecycle events reach reducers through `AsyncStream`.
- Commands run as `<shell> -ilc "<command>"` (zsh) or `--login -i -c` (bash) in the service folder.
- The app never reports a service as stopped until termination is confirmed, and never sends
  `SIGKILL` automatically.
- Running process groups are persisted in `running.json`; on launch, live groups whose leader start
  time still matches are adopted (no `Process` object, polled with `kill(-pgid, 0)`).
- A foreign process is only signaled (SIGTERM) after the user clicks **Stop It and Launch** on a port
  conflict.
- The projects file is versioned (`ProjectsDocument`); older versions are migrated on load and
  rewritten on the next save. Unknown future versions are preserved, not overwritten.

## Common changes

### Add a command detection source

1. Write a test in `StackbarTests/CommandDetectorTests.swift` with a temporary folder containing the
   manifest.
2. Add a case to `DetectedCommand.Source` (`displayName` and `shortLabel`).
3. Add a parser in `CommandDetector` and call it from `detect(in:)`. Use `looksLikeService(_:)` for
   pre-checking, and keep it root-only and dependency-free (files over 1 MB are ignored).

### Add a field to projects or services

1. Add it to `Project`/`Service` and to `ProjectDraft`/`ServiceDraft`, plus validation if needed.
2. Make decoding tolerant (`decodeIfPresent`) or bump the version in `ProjectsDocument` with a
   migration and a test in `ProjectRepositoryTests`.
3. Expose it in `PreferencesView` (`ProjectCard`).

## Testing approach

Features are built test-first: domain tests, then reducer tests with `TestStore`, then wiring and
views. Process tests (`ProjectProcessManagerTests`) start real short-lived shells.

Before a release, go through
[release-acceptance-checklist.md](release-acceptance-checklist.md) manually: UI behaviour, Gatekeeper,
login items and notifications cannot be fully covered by automated tests.

## CI and releases

- **CI** (`.github/workflows/ci.yml`): on pull requests and pushes to `main`, checks Xcode 27.2,
  generates the project and runs all tests on `macos-26`.
- **Release** (`.github/workflows/release.yml`): pushing a `v*` tag runs the tests, archives a
  universal (arm64 + x86_64) app signed ad hoc, verifies the signature and architectures, builds the
  DMG with `scripts/make-dmg.sh` and creates a **draft** GitHub release with generated notes.

```sh
git tag v0.2.0 && git push origin v0.2.0
```

Review the draft, then publish it. Builds are not notarized: that needs a Developer ID certificate
from the paid Apple Developer Program. The README explains how users open the app anyway.

## Contributing

- Keep changes small and covered by tests; run the unit tests before opening a pull request.
- Follow the existing style: 2-space indentation, value types in `Domain`, effects behind clients.
- Update the README and the acceptance checklist when user-visible behaviour changes.
