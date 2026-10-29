# Contributing to reception_flutter

This guide is for maintainers of the Flutter plugin. Customers add the plugin to their app and use the hosted Reception service and dashboard; their setup starts at [README.md](README.md) and the [Flutter guide](https://reception.sh/docs/flutter).

Read [CLAUDE.md](CLAUDE.md) before changing the plugin. It describes the repository layout, which files are generated, and the rules the plugin follows. Design decisions live in `PLAN.md`, `PUSH-DESIGN.md` and `SPEC.md`; keep them current when behaviour changes.

## Prerequisites

- Flutter 3.44 or newer (Dart 3.12, as in `pubspec.yaml`). Pigeon 29 needs Dart 3.11+, and consumers need Flutter 3.44+ anyway.
- Xcode 26 with an installed iOS simulator, booted for the native tests (`xcrun simctl boot "iPhone 17"`).
- CocoaPods, for `tool/pod_lint.sh` and for example builds with Swift Package Manager turned off.
- For SDK updates, a checkout of the native SDK at `../reception-ios`.

## Pigeon bridge

`pigeons/reception.dart` is the Dart↔Swift contract. After changing it, regenerate both sides and format the Dart output:

```sh
dart run pigeon --input pigeons/reception.dart && dart format lib/src/messages.g.dart
```

Commit `pigeons/reception.dart`, `lib/src/messages.g.dart` and `ios/reception_flutter/Sources/reception_flutter/Messages.g.swift` together. Never edit the generated files by hand; `tool/release_check.sh` fails when they differ from a fresh generation.

## Updating the bundled iOS SDK

The plugin compiles a pinned copy of the Reception iOS SDK sources (`ios/reception_flutter/Sources/reception_flutter/Vendor/Reception/`); never edit them. Vendor only released SDK versions:

```sh
dart run tool/sync_ios_sdk.dart 1.6.0     # a released tag of ../reception-ios
dart run tool/sync_ios_sdk.dart --check   # verify the files against vendor/ios-sdk.json
```

The sync updates `vendor/ios-sdk.json` and the generated `lib/src/sdk_version.dart`. Read the SDK's CHANGELOG for API or behaviour changes the plugin has to mirror (and check `../reception-react-native`, which wraps the same SDK), then re-run the full verification round per `verification/commands.txt` before releasing.

## Example app and local backend

`example/` is the verification app. Run it on a simulator against a local backend:

```sh
cd example
flutter run -d <simulator> \
  --dart-define=RECEPTION_APP_ID=<test app ID> \
  --dart-define=RECEPTION_SERVICE_URL=http://localhost:3123
```

The example passes `RECEPTION_SERVICE_URL` to `configureForTesting` from `package:reception_flutter/testing.dart`, which works only in Debug simulator builds with a localhost URL; without it the example uses the hosted service. Do not commit App IDs or identity secrets.

## Checks

`tool/release_check.sh` runs every automated check in order from the repository root and prints a summary: it requires a clean working tree, then runs analysis (plugin and example), formatting, Dart tests, the vendored SDK check, a generated-code check, the native Swift tests (needs a booted simulator), the podspec lint, an example simulator build and `flutter pub publish --dry-run`. The remaining manual checks are listed under "Checks before a release" in CLAUDE.md: the example build with SwiftPM on and off, the RunnerTests compile, and the simulator verification round. Report actual results, or the precise reason a check was not run.

## Releases

The plugin version in `pubspec.yaml` is independent of the bundled SDK version, which apps read at runtime as `Reception.version`. Bump the plugin's patch version for fixes, minor for new features or a new bundled SDK, and major only when customers must change their code. Mention the bundled SDK version in the CHANGELOG entry when it changes.

1. Start from a clean working tree on `main`.
2. Run `tool/release_check.sh` and the manual checks; all must pass.
3. Set `version` in `pubspec.yaml` and add the matching entry at the top of [CHANGELOG.md](CHANGELOG.md).
4. Commit the version bump.
5. Tag the commit: `git tag v<version>` (for example `v1.0.1`).
6. Publish: `dart pub publish`.
7. Push `main` and the tag: `git push origin main v<version>`.

Never move or delete a published tag, and never re-publish a version; release a new version instead.
