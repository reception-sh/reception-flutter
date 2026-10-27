# reception_flutter – guide for agents

Flutter plugin that adds Reception's native iOS support chat to Flutter apps. iOS only; Android and web calls are
no-ops. Customers read https://reception.sh/docs/flutter; this file is for maintainers.

## Layout

- `lib/` – Dart API (`Reception` static facade, typed options, `ReceptionChatView`). `lib/src/messages.g.dart` and
  `lib/src/sdk_version.dart` are generated.
- `pigeons/reception.dart` – the Dart↔Swift contract. Regenerate after changes:
  `dart run pigeon --input pigeons/reception.dart && dart format lib/src/messages.g.dart`.
- `ios/reception_flutter/Sources/reception_flutter/` – Swift host (Pigeon implementation, push proxy, platform view).
  `Vendor/Reception/` holds the pinned iOS SDK sources, compiled into this module; never edit them.
- `ios/reception_flutter/Package.swift` + `ios/reception_flutter.podspec` describe the same sources for SwiftPM and
  CocoaPods. Apps need no Podfile edits unless the Podfile pins an older `platform :ios` or forces
  `IPHONEOS_DEPLOYMENT_TARGET` in `post_install`; those must be 17.0 or higher.
- `vendor/ios-sdk.json` – SDK version, commit and file hashes. `dart run tool/sync_ios_sdk.dart [rev]` re-vendors
  from `../reception-ios`; `--check` verifies (run before publishing).
- `example/` – verification app against a local backend; `verification/` – evidence of the last verification round.
- `PLAN.md`, `PUSH-DESIGN.md`, `SPEC.md` – design decisions and their review outcome. Keep them current when behaviour changes.

## Rules

- Maintainers need Flutter 3.44+ (Dart 3.12, as in `pubspec.yaml`): Pigeon 29 needs Dart 3.11+, and consumers need
  Flutter 3.44+ anyway.
- Mirror the React Native wrapper (`../reception-react-native`) semantically; both wrap the same SDK.
- Keep SDK access on the main actor. Strict concurrency is on; builds must be warning-free.
- No CocoaPods Trunk: the SDK is vendored on purpose (Trunk is read-only from December 2026).
- Never add the native `reception-ios` package to an app that uses this plugin (two SDK instances would share storage).
- Push: see PUSH-DESIGN.md "Final decisions". The plugin class implements no `UNUserNotificationCenterDelegate`
  selectors; only the proxy does.

## Checks before a release

`flutter analyze`, `dart format --set-exit-if-changed .`, `flutter test`, `tool/test_native.sh` (needs a booted
simulator, or pass a device), `dart run tool/sync_ios_sdk.dart --check`, example build with SwiftPM on and off,
`tool/pod_lint.sh`,
`flutter pub publish --dry-run`, simulator verification per `verification/commands.txt`.
