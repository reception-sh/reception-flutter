# Status

## Dart layer

Implemented in `lib/` per SPEC.md "Dart public API": the static `Reception` facade (`src/reception.dart`), typed
options and events (`src/types.dart`), `ReceptionAppearance` with `copyWith`, native JSON shape and validation
(`src/appearance.dart`), snapshot mirror with per-key revisioned settings (`src/state.dart`), `ReceptionChatView`
(`src/chat_view.dart`), iOS guard and log helpers (`src/platform.dart`) and `ReceptionError` (`src/errors.dart`).
The host is connected lazily on the first real call (`connect()` + `ReceptionFlutterApi.setUp`); all host calls,
including fire-and-forget setters, await that one shared connection, and a failed connect is retried by the next
call. Unsupported platforms never reach the host. Paywall availability follows the RN request/resolve model: each
`requestPaywallAvailability` is always answered with `resolvePaywallAvailability` (false for a stale generation, a
missing, failing or replaced callback, or after 5 s), sent through the shared connection; host errors only log. Setting payloads (paywall messages, appearance JSON) are built at
assignment time, so mutating the caller's list before the connection resolves has no effect.

Tests: 59 in `test/` (Reception, settings, appearance, platforms, testing, availability timeout, exports), ported from the RN suites. Host→Dart calls
go through the real binary messenger.

Deviations and notes:
- Pigeon 29 no longer generates a test host API (`dartTestOut` was removed). `test/fake_host.dart` mocks the host
  channels with `TestDefaultBinaryMessengerBinding` and `ReceptionHostApi.pigeonChannelCodec`.
- Validation the Dart type system already guarantees (appId, identity, metadata, event and paywall shapes) is not
  repeated at runtime. Remaining runtime checks: APNs token, push payload envelope, and appearance colors
  (hex or light/dark pair), `welcomeIconSize` 16–160, `welcomeIconCornerRadius` 0–80, and a finite `welcomeIconOffset`.
- `ReceptionFontDesign.standard` maps to `"default"` (`default` is a reserved word in Dart). `welcomeIconOffset` is an `Offset`.
- Every `PlatformException` becomes `ReceptionError('bridge_error', 0)`: generic Swift errors carry private
  diagnostics in their Pigeon code. Typed SDK errors arrive only through `deleteData` and `ReceptionIdentityRejected`, as in RN.
- Events are a sealed `ReceptionEvent` with one final subclass per case (`ReceptionChatOpened`, …, `ReceptionIdentityRejected`).
- `ReceptionColor.of`/`adaptiveOf` convert Flutter `Color`s to sRGB, clamp components to 0–1 and emit `#RRGGBB`
  (opaque) or `#RRGGBBAA`.
- `package:reception_flutter/testing.dart` (not exported) offers `configureReceptionForTesting` for Debug simulator
  builds against a localhost service; native enforces the guard.
- App callbacks (`onEvent`, `onPaywall`, `paywallAvailability`) never throw into Pigeon: exceptions are reported with
  `FlutterError.reportError` (library `reception_flutter`), because Pigeon error replies with non-string details crash
  the Swift side. A throwing availability callback resolves `false`.
- Caller-owned data is copied at call time: paywalls (with unmodifiable products), metadata, and the push routing
  conversation ID are read before any await.
- `welcomeIconOffset` is limited to -1000…1000 points per axis; larger values trapped in the SDK's integer conversion.
- The example configures with `Reception.configure` unless `RECEPTION_SERVICE_URL` is defined, ships
  `example/reception-push.apns` with a placeholder conversation ID, and shows `Configured: false` when native did not
  accept the configuration.
- Every exported type is `Reception`-prefixed (`ReceptionLogLevel`, `ReceptionAppearance`, `ReceptionColor`, …;
  events `ReceptionChatOpened` … `ReceptionIdentityRejected`) to avoid `ambiguous_import` next to RevenueCat or
  Superwall. `test/exports_test.dart` fails to compile if an intended export is missing.
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
  `paywallAvailability`. `deleteData` and `registerForPushIfAuthorized` are completion-based (`@asyncCallback`): they
  run on the main actor and complete once with `.success`. `resolvePaywallAvailability` answers a pending
  availability request by id.
- `PaywallRequests.swift` (port of RN): `requestPaywallAvailability(requestId, id, generation)` is sent like
  `onState`, and Dart answers with `resolvePaywallAvailability(requestId, allowed)`. Pending requests fail closed on
  a 5 s timeout, SDK cancellation and `cancelAll()` (reconnect, callback change); late, duplicate and unknown
  answers are ignored. The channel holds no completion closures.
- `ReceptionNotifications.swift`: token cache (data + environment) applied whenever configured; after configure,
  logout and successful `deleteData` it re-applies the token and calls `registerForPushIfAuthorized()`. Pending tap
  (latest wins) drained once, 500 ms after `configure(handlesNotifications: true)` so the appearance and language
  settings Dart sends right after configure apply first (a later configure reschedules it), discarded by an opt-out
  configure.
  `ReceptionNotificationCenter` proxy installed once at the first handling configure, wraps the previous delegate,
  handles Reception payloads (receipt → `[]` while chat open else `[.banner, .list, .sound]`; default-action tap →
  open; other actions only complete), forwards everything else through `OnceCompletion` (exactly once;
  fallback `[]` after 2 s for `willPresent`, logged once at info level because a wrapped firebase_messaging never
  answers notifications it no longer owns; `()` after 10 s for `didReceive`), forwards `openSettingsFor`. A later opt-out makes it pass-through and restores the previous
  delegate if it still owns the center; a replacement by someone else is logged once (info) and never re-wrapped.
- `NotificationRouting.swift` (RN state machine, at most 64 keys, oldest evicted first; after the legacy launch tap is
  drained, only the first proxy tap for its conversation that was delivered before this launch and arrives within
  10 s of the drain is recorded as opened instead of reopening the chat; then the marker clears and every tap
  routes), `OnceCompletion.swift`,
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
  `PaywallRequests` with `tool/native_tests/LogicTests.swift` (macOS, incl. the launch tap rule and late replies
  after cancellation, reconnect and timeout, duplicate and unknown answers) and `ReceptionColor` with
  `ReceptionColorTests.swift` (simulator); all pass.
- Builds use the example app as committed; runtime behaviour is covered under "Verification" below.

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

Known limitations:
- Cancellation does not finish Pigeon continuations. Fire-and-forget calls to Dart (`onState`, `onEvent`,
  `onPaywall`, `requestPaywallAvailability`) run in per-connection tasks that `invalidate()` cancels; a task whose
  connection has ended skips sending. A continuation already awaiting an acknowledgement from an
  isolate that died at that instant stays suspended until process exit. Debug only (hot restart), bounded by the
  calls in flight at that moment.

Other changes after review: `welcomeIconOffset` components outside -1000…1000 are ignored (the SDK's appearance
report traps on huge values); calls to Dart queued for an earlier connection are skipped by a connection token;
`example/ios/RunnerTests` imports the plugin module and tests `PushToken` and `NotificationRouting`
(`build-for-testing` succeeds; it needs any Flutter build of the example first to generate the SwiftPM package).
The connection-token check is one comparison inside `ReceptionHost`, which depends on Flutter and the SDK, so it has
no native unit test.

Open questions: none.

## Upstream SDK follow-ups (reception-ios)

To fix in the SDK and re-vendor with the next SDK release:
- `DeviceStore.clear()` omits the persisted `subscriptionStates` key, so stale dictionaries stay in UserDefaults after
  logout and deletion (`Vendor/Reception/Sources/Reception/Client/DeviceStore.swift:148`).
- German string for a failed image download says "Erneut senden" instead of "Erneut versuchen"
  (`Localizable.xcstrings` around line 7340, used by `RemoteAttachmentImage.swift:21`).
- A changed `appearance.preferredColorScheme` is not applied to an already presented chat (accent color and language
  do update), observed in the customer walkthrough.

## Verification

Final simulator verification of the example app on the final plugin code (main at a2b487f: Dart connection path,
request/resolve paywall availability, launch-tap dedupe, callback guards, color conversion), 2026-10-27
18:41–19:02 CET, Flutter 3.47.8, Xcode 26.5, iPhone 17 Pro / iOS 26.5, local backend on :3123. Exact commands,
results and evidence: `verification/commands.txt`, `verification/screenshots.txt`, `verification/*.log`; summary in
German: `verification/EXPLAINER.md`. This supersedes the earlier rounds and the notes above that the example is
still the template and that runtime behaviour is unverified.

Example: `example/lib/main.dart` exercises the whole public API (configure at startup when
`RECEPTION_APP_ID` is defined, `RECEPTION_AUTOSTART=false` for the Configure button), `example/integration_test/`
drives it on a simulator, `example/ios/Runner/AppDelegate.swift` adds the example's own notification-permission
channel (`xcrun simctl privacy` has no notifications service), `Info.plist` declares `en`/`de` localizations, and
`Runner/Runner.entitlements` adds the Push Notifications entitlement (`aps-environment` development).

All sections passed:
- a. analyze, format, 51 Dart tests, SDK sync check (107 files), native tests (incl. launch-tap dedupe and
  duplicate/unknown/late availability answers), pod lint with `LANG` unset, `flutter pub publish --dry-run`
  (204 KB, 0 warnings).
- b. clean SwiftPM build (0 warning lines), setup check, both previews, integration test (1 test).
- c. inbox reply → unread badge → reply in chat; identity and metadata in the inbox details; `hidden` absent from
  the Send offer dialog; offer card tap → `paywallOpened` and `onPaywall('plans')` with the chat still open;
  review card tap → `reviewOpened` (iOS hands the App Store link to Safari on the simulator; the app keeps running).
- d. simulator APNs token registered (sandbox); foreground banner with chat closed and unread refreshed by the
  receipt; no banner with chat open; background tap and cold-start tap open the chat; a second push tapped 33 s
  after the cold-start tap opens the chat again (the dedupe only suppresses the repeated launch tap).
- e. CocoaPods build, setup check and German strings from `Reception.bundle`; SwiftPM restored, no artifacts.
- f. hot restart under `flutter run`: unread and configuration re-read, availability (including the hanging
  callback failing closed and restoring) works.
- g. language override, dark/light, embedded view, deleteData (`dataDeleted`, server data gone), logout (empty chat).
- h. fresh `flutter create` app: SwiftPM and CocoaPods builds after raising the deployment target, no Podfile edits.

Final re-check on main at 6a2a7b0 (after 12dbdc0 launch-tap suppression limited to one duplicate within 10 s, and
a98bb28 per-connection call tracking), 2026-10-27 19:10–19:23 CET: analyze, 51 Dart tests, native tests (incl.
launch-tap dedupe), clean SwiftPM build (0 warnings), integration test, setup check, background tap, cold-start tap,
a second push for the same conversation tapped 31 s after the cold start (opens the chat again), and hot restart
with the availability check all pass (`verification/commands.txt` "FINAL RE-CHECK", `verification/recheck-*.log`).

Observed, not bugs: `setPushToken` called before configure is cached by the plugin and applied after configure (as
PUSH-DESIGN specifies), so the example's "Calls before configure" registers its dummy `aabb` token until the real
APNs token replaces it; `flutter test integration_test` uninstalls the app afterwards (the next install is a new
device with a new conversation) and leaves its test-harness build in `example/build/ios/iphonesimulator/Runner.app`,
which shows a white screen when launched standalone; rebuild the example before installing it.

Not verified: real APNs delivery from the backend to a physical device (pushes were simulated with
`xcrun simctl push`); the App Store review sheet itself (no App Store on the simulator); a server-side
`ReceptionIdentityRejected` (a malformed token is ignored locally by the SDK with "Identity token ignored, its user_id
could not be read"); automations reacting to `track`; photo sending; release builds; Android/web at runtime (unit
tests only).

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
   ("may not be compatible … minimum requirement of iOS 17.0"; checked in the first round). The guide's advice is correct, but "Flutter apps
   need no Podfile edits" holds even without it.
4. Local verification environment (not the guide): the backend's `AUTH_URL=http://localhost:3000` sends the
   post-login redirect of the :3123 dev server to :3000; `local-test@example.test` is not a member of the
   Flutter Example organization (its only member is the workspace owner).

## Customer walkthrough

2026-10-27, 20:20–21:00 CET, evidence in `verification/customer-walkthrough/` (`commands.txt`, `GAPS.md`,
`integration.diff`, screenshots 01–24). An agent followed the dashboard setup prompt literally on a fresh
`flutter create` app (Home, Settings, light/dark setting, in-app English/German, name-only sign-in, fake paywall
without a store library), with a path dependency and `configureReceptionForTesting` against the local service as the
only deviations. Docs, prompt and plugin changed mid-run (Reception-prefixed types, entitlements file, iOS-only
entry); the app was updated to the current text, rebuilt and checked again.

PASS: package, deployment target, configure, docs comment, AGENTS.md, appearance from the theme (dark mode), German
language override, Support icon button on Home and Settings row with live badges, identify with the entered name,
metadata plan and sign-up date, logout on sign-out (new empty chat), entitlements without Xcode, build and install
commands, setup check (passed on the first launch, twice), welcome and conversation previews, dashboard reply as the
badge and in the chat, own-screen paywall card (sheet closes, Flutter paywall opens, chat reopens).

Round 1–2 could not show a push banner: the app had no permission flow and the docs gave no Flutter way to add one.

Round 3 (21:00–21:10), after the docs and prompt were updated from `GAPS.md`: the app asks for notification
permission with flutter_local_notifications when the user turns on its daily reminder, exactly as `flutter.md#push`
shows, then calls `registerForPushIfAuthorized()`. PASS: permission granted, sandbox token registered, foreground
banner, background tap opens chat, cold-start tap opens chat; the store-agnostic own-screen paywall file (copied
unchanged, `ownedProductIds: () async => <String>{}`) opens the paywall from an offer card and reopens chat; the
appearance and Badge snippets compile verbatim.

Closed: G1 push permission, G2 paywall without a store library, G3 Material theme mapping, G4 languageOverride type,
G5 name-only sign-in, G7 badge snippet. Open: G6 badge "on the way" vs. a toolbar button on the same screen; G8
paywall helper account switch without vendor accounts; G9 English example messages in previews of a German app;
G10 flutter_local_notifications must be initialized without its launch prompt (docs); F1 (plugin): a cold-start
notification tap opens the chat inside `configure`, before Dart assigns the appearance, so a dark app's chat opens
light (`ReceptionNotifications.configured` routes the launch tap; a later `preferredColorScheme` does not reach the
open sheet). Details and fix text in `GAPS.md`.
