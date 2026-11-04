# Stackbar

Stackbar is a native macOS menu bar app for configuring, launching, and monitoring local development projects.

**Status:** early development. macOS 26 or newer is required.

## Build and test

Install Xcode 27.2 and [XcodeGen](https://github.com/yonaskolb/XcodeGen), then run:

```sh
xcodegen generate
xcodebuild -skipMacroValidation -project Stackbar.xcodeproj -scheme Stackbar \
  -destination 'platform=macOS,arch=arm64' build
```

Run the unit and UI tests with the same options and `test` instead of `build`. The pinned TCA macro
packages require `-skipMacroValidation` for non-interactive Xcode builds in this environment.
If `xcode-select -p` points to Command Line Tools rather than Xcode, set `DEVELOPER_DIR` to your
Xcode installation's `Contents/Developer` directory before running `xcodebuild`.

## Install a release

Open the DMG and drag `Stackbar.app` to `Applications`. Releases are ad hoc signed and not notarized,
so macOS may show a Gatekeeper warning. If macOS blocks the app, open **System Settings > Privacy &
Security**, choose **Open Anyway** for Stackbar, then confirm the prompt. Releases do not include an
auto-updater; check GitHub Releases for updates.

Third-party dependency and license references are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Local data

Project settings are stored in `~/Library/Application Support/Stackbar/`; logs are kept in memory
only. Neither is part of this repository.

## License

Stackbar is available under the MIT license. See [LICENSE](LICENSE).
