# Status

## Dart layer

Implemented in `lib/` per SPEC.md "Dart public API": the static `Reception` facade (`src/reception.dart`), typed
options and events (`src/types.dart`), `Appearance` with `copyWith`, native JSON shape and validation
(`src/appearance.dart`), snapshot mirror with per-key revisioned settings (`src/state.dart`), `ReceptionChatView`
(`src/chat_view.dart`), iOS guard and log helpers (`src/platform.dart`) and `ReceptionError` (`src/errors.dart`).
The host is connected lazily on the first real call (`connect()` + `ReceptionFlutterApi.setUp`); unsupported
platforms never reach it.

Tests: 45 in `test/` (Reception, settings, appearance, platforms, testing), ported from the RN suites. Host→Dart calls
go through the real binary messenger.

Deviations and notes:
- Pigeon 29 no longer generates a test host API (`dartTestOut` was removed). `test/fake_host.dart` mocks the host
  channels with `TestDefaultBinaryMessengerBinding` and `ReceptionHostApi.pigeonChannelCodec`.
- Validation the Dart type system already guarantees (appId, identity, metadata, event and paywall shapes) is not
  repeated at runtime. Remaining runtime checks: APNs token, push payload envelope, and appearance colors
  (hex or light/dark pair), `welcomeIconSize` 16–160, `welcomeIconCornerRadius` 0–80, and a finite `welcomeIconOffset`.
- `FontDesign.standard` maps to `"default"` (`default` is a reserved word in Dart). `welcomeIconOffset` is an `Offset`.
- Every `PlatformException` becomes `ReceptionError('bridge_error', 0)`: generic Swift errors carry private
  diagnostics in their Pigeon code. Typed SDK errors arrive only through `deleteData` and `IdentityRejectedEvent`, as in RN.
- Events are a sealed `ReceptionEvent` with one final subclass per case (`ChatOpenedEvent`, …, `IdentityRejectedEvent`).
- `AppearanceColor.of`/`adaptiveOf` convert Flutter `Color`s to `#RRGGBB` (opaque) or `#RRGGBBAA`.
- `package:reception_flutter/testing.dart` (not exported) offers `configureReceptionForTesting` for Debug simulator
  builds against a localhost service; native enforces the guard.
- `resetReception()` (`@visibleForTesting`, not exported) simulates a hot restart in tests.

## iOS host

Implemented in `ios/reception_flutter/Sources/reception_flutter/` per SPEC.md "iOS host" and PUSH-DESIGN.md
"Final decisions after review":
- `ReceptionFlutterPlugin.swift`: registers the Pigeon host API, the `reception_flutter/chat` view factory, and the
  plugin as application and scene delegate (`registrar.publish` keeps it alive). Launch capture
  (`launchOptions[.remoteNotification]`, key `"launch"`), scene capture (`connectionOptions.notificationResponse`,
  default action only, returns `false`), foreground `registerForPushIfAuthorized` on `applicationDidBecomeActive` /
  `sceneDidBecomeActive`, token capture, fetch callback as receipt only (`.noData`, `true` only for Reception
  payloads). Implements no `userNotificationCenter…` selector (checked in the generated `-Swift.h`).
- `ReceptionHost.swift`: the `ReceptionHostApi` (port of RN `ReceptionBridge` + `ReceptionModule`): `connect`
  replaces the previous connection (cancels pending availability checks, clears `onEvent`/`onPaywall`, keeps
  `paywallAvailability = { _ in false }` if one was set, new observation token), revisioned snapshots,
  `withObservationTracking` → `onState`, per-key setting revisions, events, `deleteData` typed errors
  (`bridge_error`/0 otherwise), `configureForTesting` only under `#if DEBUG` and only for localhost/127.0.0.1/::1 over
  http(s). `deleteData` and `registerForPushIfAuthorized` are completion-based (`@asyncCallback`): they run on the
  main actor and complete once with `.success`.
- `PaywallRequests.swift`: races `checkPaywallAvailability(id, generation)` against a 5 s timeout, SDK cancellation
  and `cancelAll()` (reconnect, callback change); any failure is `false`.
- `ReceptionNotifications.swift`: token cache (data + environment) applied whenever configured; after configure,
  logout and successful `deleteData` it re-applies the token and calls `registerForPushIfAuthorized()`. Pending tap
  (latest wins) drained once by `configure(handlesNotifications: true)`, discarded by an opt-out configure.
  `ReceptionNotificationCenter` proxy installed once at the first handling configure, wraps the previous delegate,
  handles Reception payloads (receipt → `[]` while chat open else `[.banner, .list, .sound]`; default-action tap →
  open; other actions only complete), forwards everything else through `OnceCompletion` (exactly once, 10 s
  fallback `[]`/`()`), forwards `openSettingsFor`. A later opt-out makes it pass-through and restores the previous
  delegate if it still owns the center; a replacement by someone else is logged once (info) and never re-wrapped.
- `NotificationRouting.swift` (RN state machine, at most 64 keys, oldest evicted first), `OnceCompletion.swift`,
  `PushToken.swift`, `ReceptionColor.swift`, `ReceptionAppearance.swift`, `PaywallValues.swift`,
  `ReceptionChatPlatformView.swift` (hosts `UIHostingController(rootView: ReceptionChatView())` as a child of the
  nearest view controller while in a window, removes it when leaving the window). Logger subsystem
  `com.reception.flutter`; tokens and payloads are never logged.

Verification (Flutter 3.47.8, Xcode 26.5, 2026-10-27):
- SwiftPM (default): `cd example && flutter build ios --simulator --debug` → built. Clean `xcodebuild` of the
  workspace: 0 compiler warnings, generated `Messages.g.swift` included. The only `warning:` line in the log is
  Xcode's `appintentsmetadataprocessor`: "Metadata extraction skipped. No AppIntents.framework dependency found."
  `Runner.app/reception_flutter_reception_flutter.bundle` contains `PrivacyInfo.xcprivacy` and 48 `*.lproj/Localizable.strings` compiled from `Localizable.xcstrings`.
- CocoaPods: `flutter config --no-enable-swift-package-manager && cd example && flutter build ios --simulator --debug`
  → built (SwiftPM re-enabled afterwards). Clean `xcodebuild`: 0 compiler warnings, generated code included (same
  AppIntents note only). `Runner.app/Frameworks/reception_flutter.framework/Reception.bundle`
  contains `PrivacyInfo.xcprivacy` and the 48 string tables; with `use_frameworks! :linkage => :static` the bundle
  is at `Runner.app/Reception.bundle`, where the SDK's `Bundle(for:)` lookup (main bundle) finds it.
- `tool/pod_lint.sh`: Trunk's `Flutter` pod (last real release 2020) lacks `FlutterSceneLifeCycleDelegate` /
  `addSceneDelegate`, so the script lints against a temporary lint-only `Flutter` podspec vendoring the installed
  engine's `Flutter.xcframework`, with `--use-modular-headers` and `--use-libraries`. Both pass; the only warning is
  the plugin podspec's `:path` source ("Missing primary key for `source` attribute"), standard for Flutter plugins,
  which needs `--allow-warnings`; the script then prints the warnings and fails on any other.
- `tool/test_native.sh` (needs a booted simulator, or pass a device): `swiftc -swift-version 5
  -strict-concurrency=complete -warnings-as-errors` builds `PushToken`, `NotificationRouting`, `OnceCompletion`,
  `PaywallRequests` with `tool/native_tests/LogicTests.swift` (macOS) and `ReceptionColor` with
  `ReceptionColorTests.swift` (simulator); all pass.
- The example's `lib/main.dart` is still the template (does not compile against the Dart API), so builds used a
  temporary minimal `main.dart`; it was restored. Runtime behaviour (push, cold start, platform view) is not yet
  verified on a simulator.

Deviations:
- One `ReceptionHost` per engine instead of a literal `ReceptionHost.shared`: Pigeon's `connect()` carries no engine
  identity, so each engine's host owns its `ReceptionFlutterApi`; shared state is static (current connection,
  snapshot revision, accepted appearance) exactly like RN's `ReceptionBridge`, and the latest `connect()` wins
  process-wide. Push state is the process-wide `ReceptionNotifications.shared`.
- `connect()` resets setting revisions: a hot restart reuses the native host while Dart's counters restart at zero.
- The plugin, the notification proxy and the host API are `@MainActor` with `@preconcurrency` conformances
  (Flutter, UIKit and Pigeon call them on the main thread) instead of
  `MainActor.assumeIsolated` bodies: under CocoaPods (`SWIFT_STRICT_CONCURRENCY=complete`, region isolation),
  capturing non-Sendable arguments such as UIKit objects and Pigeon completion handlers in `assumeIsolated` closures
  warned. `version()` stays nonisolated.
- Fetch-callback receipts call the SDK directly instead of going through `NotificationRouting`: that callback has no
  request identifier, so its key could never match a `willPresent` or tap key and would only take one of the 64 slots.
- Routing keys: `identifier|date` (proxy and scene path), `"launch"` (legacy cold start).
- Pending taps, token application and proxy installation wait for a configure that succeeded
  (`Reception.isConfigured`); a malformed App ID changes nothing.
- `example/ios/Runner.xcodeproj`: removed the template's folder reference to `../../ios/reception_flutter`. Xcode
  treated it as a local package override with identity `reception_flutter`, while Flutter symlinks the plugin under
  the checkout directory name (`reception-flutter`), so SwiftPM resolution failed.

Open questions:
- Runtime behaviour (push receipt and taps, cold start, platform view) still needs simulator verification with the
  example app.
