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
  same, plus `ReceptionPushReceiver` (Android push, PUSH-DESIGN.md "Android"), `OverlapInsets` and `ActivityResults`
  (embedded chat). It depends on `sh.reception:reception:<version>` from Maven Central, which must equal
  `lib/src/android_sdk_version.dart` (a Dart test checks it). Never add `mavenLocal()` to `android/build.gradle.kts`.
- `vendor/ios-sdk.json` – SDK version, commit and file hashes. `dart run tool/sync_ios_sdk.dart [rev]` re-vendors
  from `../reception-ios`; `--check` verifies (run before publishing).
- `example/` – verification app against a local backend; `verification/` – evidence of the last verification round.
- `PLAN.md`, `PUSH-DESIGN.md`, `SPEC.md` – design decisions and their review outcome. Keep them current when behaviour changes.

## Android SDK before it is on Maven Central

Until `sh.reception:reception` is published, publish it locally and build the example (whose
`android/build.gradle.kts`, not the plugin's, lists `mavenLocal()`). Never run Gradle in `../reception-android`
while another agent builds there; use a copy of its HEAD:

```sh
git -C ../reception-android archive HEAD | tar -x -C /tmp/reception-android-src
cp ../reception-android/local.properties /tmp/reception-android-src/
(cd /tmp/reception-android-src && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew :reception:publishToMavenLocal)
```

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
- Push: see PUSH-DESIGN.md "Final decisions" (iOS) and "Android". The plugin class implements no
  `UNUserNotificationCenterDelegate` selectors; only the proxy does. On Android the SDK owns notification taps.
- Android: SDK calls only on the main thread (Pigeon calls there); Kotlin builds must be warning-free.

## Checks before a release

`tool/release_check.sh` runs the automated checks in one command (clean tree required; see CONTRIBUTING.md). Individually:
`flutter analyze`, `dart format --set-exit-if-changed .`, `flutter test`, `tool/test_native.sh` (needs a booted
simulator, or pass a device), `dart run tool/sync_ios_sdk.dart --check`, example build with SwiftPM on and off,
`tool/pod_lint.sh`, RunnerTests compile (after any Flutter build of the example, e.g. `flutter build ios
--config-only --simulator`): `xcodebuild -workspace example/ios/Runner.xcworkspace -scheme Runner -destination
'platform=iOS Simulator,id=1B82EA4D-9E6C-401B-9BF1-DF6EEE286309' build-for-testing`,
`flutter pub publish --dry-run`, simulator verification per `verification/commands.txt`. Android: `flutter build apk
--release` of the example (R8), the Android unit tests, emulator verification per `verification/android.md`.
