# reception_flutter – guide for agents

Flutter plugin that adds Reception's native support chat to Flutter apps on iOS and Android. Web and desktop calls
are no-ops. Customers read https://reception.sh/docs/flutter; this file is for maintainers.

## Layout

- `lib/` – Dart API (`Reception` static facade, typed options, `ReceptionChatView`). `lib/src/messages.g.dart` and
  `lib/src/sdk_version.dart` are generated.
- `pigeons/reception.dart` – the Dart↔Swift/Kotlin contract. Regenerate after changes:
  `dart run pigeon --input pigeons/reception.dart && dart format lib/src/messages.g.dart` (also writes
  `Messages.g.swift` and `android/…/Messages.g.kt`).
- `ios/reception_flutter/Sources/reception_flutter/` – Swift host (Pigeon implementation, push proxy, platform view).
  `Vendor/Reception/` holds the pinned iOS SDK sources, compiled into this module; never edit them.
- `ios/reception_flutter/Package.swift` + `ios/reception_flutter.podspec` describe the same sources for SwiftPM and
  CocoaPods. Apps need no Podfile edits unless the Podfile pins an older `platform :ios` or forces
  `IPHONEOS_DEPLOYMENT_TARGET` in `post_install`; those must be 17.0 or higher.
- `android/` – Kotlin host (package `sh.reception.flutter`), one file per Swift host file where the behaviour is the
  same, plus `ReceptionPushReceiver` (Android push) and `ActivityResults` (embedded chat).
  The SDK pads an embedded chat only where the window's insets overlap it; never trim insets in the plugin. It
  depends on `sh.reception:reception:<version>` from Maven Central, which must equal `lib/src/android_sdk_version.dart`
  (a Dart test checks it). Never add `mavenLocal()` to `android/build.gradle.kts`.
- `vendor/ios-sdk.json` – SDK version, commit and file hashes. `dart run tool/sync_ios_sdk.dart [rev]` re-vendors
  from `../reception-ios`; `--check` verifies (run before publishing).
- `example/` – verification app against a local backend.
- The maintainers' notes (design decisions for the plugin and its push handling, the specification, the verification
  commands and their evidence) are kept outside this repository, in `../reception-internal/flutter/`. Keep them
  current when behaviour changes.

## Android example

The plugin and the example resolve `sh.reception:reception` from Maven Central. To try an unreleased SDK, publish it to
Maven Local from a copy of `../reception-android` and add `mavenLocal()` to the example's `android/build.gradle.kts`
for that build only; never commit it and never add it to the plugin's own build file.

The example's Firebase configuration (`example/android/app/google-services.json`, Firebase project
`reception-android-test`, app `sh.reception.receptionFlutterExample`) is not committed; without it the example
builds without push. Android unit tests: `cd example/android && ./gradlew :reception_flutter:testDebugUnitTest`.

## Rules

- Maintainers need Flutter 3.44+ (Dart 3.12, as in `pubspec.yaml`): Pigeon 29 needs Dart 3.11+, and consumers need
  Flutter 3.44+ anyway.
- Mirror the React Native wrapper (`../reception-react-native`) semantically; both wrap the same SDK.
- Keep SDK access on the main actor. Strict concurrency is on; builds must be warning-free.
- No CocoaPods Trunk: the SDK is vendored on purpose (Trunk is read-only from December 2026).
- Never add the native `reception-ios` package to an app that uses this plugin (two SDK instances would share storage).
- Push: the maintainers' push design notes hold the decisions for iOS and Android. The plugin class implements no
  `UNUserNotificationCenterDelegate` selectors; only the proxy does. On Android the SDK owns notification taps.
- Android: SDK calls only on the main thread (Pigeon calls there); Kotlin builds must be warning-free.

## Known limits

- Android: with Impeller (Flutter's default renderer), a cached-engine activity recreated while a platform view is
  on screen can draw Flutter's own surface black on the Android emulator (`EGL_BAD_ACCESS`; untested on physical
  devices). It reproduces with a plain `View`, so it comes from Flutter's hybrid composition, not the plugin.
  `--no-enable-impeller` avoids it.

## Checks before a release

`tool/release_check.sh` runs the automated checks in one command (clean tree required; see CONTRIBUTING.md). Individually:
`flutter analyze`, `dart format --set-exit-if-changed .`, `flutter test`, `tool/test_native.sh` (needs a booted
simulator, or pass a device), `dart run tool/sync_ios_sdk.dart --check`, example build with SwiftPM on and off,
`tool/pod_lint.sh`, RunnerTests compile (after any Flutter build of the example, e.g. `flutter build ios
--config-only --simulator`): `xcodebuild -workspace example/ios/Runner.xcworkspace -scheme Runner -destination
'platform=iOS Simulator,id=1B82EA4D-9E6C-401B-9BF1-DF6EEE286309' build-for-testing`,
`flutter pub publish --dry-run`, simulator verification per the maintainers' notes (`commands.txt`). Android: `flutter
build apk --release` of the example (R8), the Android unit tests, emulator verification per the maintainers' notes
(`android.md`).
