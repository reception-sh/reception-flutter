# Status

## Dart layer

Implemented in `lib/` per SPEC.md "Dart public API": the static `Reception` facade (`src/reception.dart`), typed
options and events (`src/types.dart`), `Appearance` with `copyWith`, native JSON shape and validation
(`src/appearance.dart`), snapshot mirror with per-key revisioned settings (`src/state.dart`), `ReceptionChatView`
(`src/chat_view.dart`), iOS guard and log helpers (`src/platform.dart`) and `ReceptionError` (`src/errors.dart`).
The host is connected lazily on the first real call (`connect()` + `ReceptionFlutterApi.setUp`); all host calls,
including fire-and-forget setters, await that one shared connection, and a failed connect is retried by the next
call. Unsupported platforms never reach the host. Paywall availability callbacks are answered within 5 s (false on
timeout) so native never waits indefinitely. Setting payloads (paywall messages, appearance JSON) are built at
assignment time, so mutating the caller's list before the connection resolves has no effect.

Tests: 50 in `test/` (Reception, settings, appearance, platforms, testing, availability timeout), ported from the RN suites. Host→Dart calls
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
- `AppearanceColor.of`/`adaptiveOf` convert Flutter `Color`s to sRGB, clamp components to 0–1 and emit `#RRGGBB`
  (opaque) or `#RRGGBBAA`.
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
  (`bridge_error`/0 otherwise), `configureForTesting` only under `#if DEBUG && targetEnvironment(simulator)` and only
  for localhost/127.0.0.1/::1 over http(s). `configure` with an App ID the SDK rejects (`ReceptionAPI.accepts`)
  returns the snapshot and leaves configuration and push ownership unchanged; a repeated accepted App ID re-applies
  notification handling. Only the current connection (`connected && current === self`) may change `onPaywall` and
  `paywallAvailability`. `deleteData` and `registerForPushIfAuthorized` are completion-based (`@asyncCallback`): they run on the
  main actor and complete once with `.success`.
- `PaywallRequests.swift`: asks Dart with the completion-based `checkPaywallAvailability(id, generation)`; the reply
  closure holds only the request id and a weak reference and hops to the main actor (Flutter's reply block is
  imported as `@Sendable`). The SDK-facing request fails closed on a 5 s timeout, SDK cancellation and `cancelAll()`
  (reconnect, callback change); a late or lost reply is ignored and keeps no task alive.
- `ReceptionNotifications.swift`: token cache (data + environment) applied whenever configured; after configure,
  logout and successful `deleteData` it re-applies the token and calls `registerForPushIfAuthorized()`. Pending tap
  (latest wins) drained once by `configure(handlesNotifications: true)`, discarded by an opt-out configure.
  `ReceptionNotificationCenter` proxy installed once at the first handling configure, wraps the previous delegate,
  handles Reception payloads (receipt → `[]` while chat open else `[.banner, .list, .sound]`; default-action tap →
  open; other actions only complete), forwards everything else through `OnceCompletion` (exactly once, 10 s
  fallback `[]`/`()`), forwards `openSettingsFor`. A later opt-out makes it pass-through and restores the previous
  delegate if it still owns the center; a replacement by someone else is logged once (info) and never re-wrapped.
- `NotificationRouting.swift` (RN state machine, at most 64 keys, oldest evicted first; after the legacy launch tap is
  drained, a first proxy tap for its conversation whose notification was delivered before this launch is recorded as
  opened instead of reopening the chat; anything delivered after launch routes), `OnceCompletion.swift`,
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
  → built (SwiftPM re-enabled afterwards). Clean `xcodebuild`: 0 warnings in plugin sources; since the FlutterApi
  availability call became `@asyncCallback`, one generated warning at `Messages.g.swift:1065` (see open questions). `Runner.app/Frameworks/reception_flutter.framework/Reception.bundle`
  contains `PrivacyInfo.xcprivacy` and the 48 string tables; with `use_frameworks! :linkage => :static` the bundle
  is at `Runner.app/Reception.bundle`, where the SDK's `Bundle(for:)` lookup (main bundle) finds it.
- `tool/pod_lint.sh`: Trunk's `Flutter` pod (last real release 2020) lacks `FlutterSceneLifeCycleDelegate` /
  `addSceneDelegate`, so the script lints against a temporary lint-only `Flutter` podspec vendoring the installed
  engine's `Flutter.xcframework`, with `--use-modular-headers` and `--use-libraries`. Passed before the
  `@asyncCallback` FlutterApi change, whose generated warning now fails it (see open questions); otherwise the only
  warning is the plugin podspec's `:path` source ("Missing primary key for `source` attribute"), standard for Flutter plugins,
  which needs `--allow-warnings`; the script then prints the warnings and fails on any other.
- `tool/test_native.sh` (needs a booted simulator, or pass a device): `swiftc -swift-version 5
  -strict-concurrency=complete -warnings-as-errors` builds `PushToken`, `NotificationRouting`, `OnceCompletion`,
  `PaywallRequests` with `tool/native_tests/LogicTests.swift` (macOS, incl. the launch tap rule and late replies
  after cancellation, reconnect and timeout) and `ReceptionColor` with
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
- Generated code warning (CocoaPods build, `pod lib lint`; SwiftPM shows none): `Messages.g.swift:1065:9: warning:
  capture of 'completion' with non-Sendable type '(Result<Bool, ReceptionBridgeError>) -> Void' in a '@Sendable'
  closure`. Pigeon 29's callback-style FlutterApi (`@asyncCallback` on `checkPaywallAvailability`) captures the
  completion in Flutter's reply block, which Swift imports as `@Sendable`; the other FlutterApi methods capture a
  Sendable continuation and do not warn. `tool/pod_lint.sh` fails on it by design. Options: accept and allow this one
  warning, or go back to `@async` (a lost reply then keeps one suspended task per unanswered request).
- Runtime behaviour (push receipt and taps, cold start, platform view) still needs simulator verification with the
  example app.

## Verification

Simulator verification of the example app (Flutter 3.47.8, Xcode 26.5, iPhone 17 Pro / iOS 26.5, local backend on
:3123, 2026-10-27). Exact commands, results and evidence: `verification/commands.txt`, `verification/screenshots.txt`,
`verification/*.log`; summary in German: `verification/EXPLAINER.md`. This supersedes the notes above that the
example is still the template and that runtime behaviour is unverified.

Example: `example/lib/main.dart` exercises the whole public API (configure at startup when
`RECEPTION_APP_ID` is defined, `RECEPTION_AUTOSTART=false` for the Configure button), `example/integration_test/`
drives it on a simulator, `example/ios/Runner/AppDelegate.swift` adds the example's own notification-permission
channel (`xcrun simctl privacy` has no notifications service), `Info.plist` declares `en`/`de` localizations, and
`Runner/Runner.entitlements` adds the Push Notifications entitlement (`aps-environment` development).

Passed: analyze, format, 45 Dart tests, SDK sync check, native tests, pod lint, `flutter pub publish --dry-run`
(0 warnings), SwiftPM and CocoaPods builds and setup checks, previews, integration test, dashboard reply → unread badge → reply in chat,
identity and metadata in the inbox details, `hidden` never offered (also absent from the Send offer dialog), offer
card tap (`paywallOpened`, `onPaywall('plans')` with the chat still open, click recorded), simulator APNs token
registered (sandbox) after `registerForPushIfAuthorized`, foreground banner with chat closed,
no banner with chat open, receipt refreshes unread, background tap and cold-start tap open the chat, German via
device language (both package managers) and via `languageOverride`, light/dark, embedded view, deleteData
(`dataDeleted`, server data gone), logout (empty chat), hot restart (state re-read, availability works), and a
fresh `flutter create` app with SwiftPM and CocoaPods without Podfile edits.

Not verified: the review card (`reviewOpened`) — the dashboard disables it until the app has an App Store ID,
and none was invented; real APNs delivery from the backend (pushes were simulated with `xcrun simctl push`); a
server-side `IdentityRejectedEvent` (a malformed token is ignored locally by the SDK with "Identity token ignored,
its user_id could not be read"); automations; photos; release builds.

### Bugs found during verification

None open. The two found in the first round (`meta` missing from `dependencies`; `tool/pod_lint.sh` failing
without a UTF-8 locale) were fixed in 8b37473 and re-verified: the publish dry-run reports 0 warnings and pod
lint passes with `LANG`/`LC_ALL` unset.

### Docs discrepancies

Against `reception/content/docs/flutter.md` (served at /docs/flutter):

1. Install: "set `IPHONEOS_DEPLOYMENT_TARGET = 17.0` for the Runner target's Debug, Release, and Profile
   configurations". In a `flutter create` project the three `IPHONEOS_DEPLOYMENT_TARGET = 15.0` lines are in the
   project-level build configurations; the Runner target has none and inherits them. Editing those three lines
   (or Xcode's Minimum Deployments, which adds target-level values) works. Suggest: "in `ios/Runner.xcodeproj`,
   change every `IPHONEOS_DEPLOYMENT_TARGET` to 17.0". Without it SwiftPM fails with "The package product
   'reception-flutter' requires minimum platform version 17.0".
2. Appearance and language: "Set `languageOverride = null` to follow the app's selected iOS localization." A
   Flutter app that declares no `CFBundleLocalizations` in `ios/Runner/Info.plist` (the template declares none)
   is resolved to English by iOS, so the chat stays English on a German device. Verified: English with
   `-AppleLanguages '(de)'`, German after adding `CFBundleLocalizations` `[en, de]`. Suggest a sentence: list the
   app's languages under `CFBundleLocalizations` in `ios/Runner/Info.plist`, as Flutter's internationalization
   guide requires for iOS.
3. Install (CocoaPods): the Podfile platform line is optional in practice. The generated Podfile keeps
   `# platform :ios, '15.0'` commented and builds; an explicit `'15.0'` still builds with a CocoaPods warning
   ("may not be compatible … minimum requirement of iOS 17.0"). The guide's advice is correct, but "Flutter apps
   need no Podfile edits" holds even without it.
4. Local verification environment (not the guide): the backend's `AUTH_URL=http://localhost:3000` sends the
   post-login redirect of the :3123 dev server to :3000; `local-test@example.test` is not a member of the
   Flutter Example organization (its only member is the workspace owner).
