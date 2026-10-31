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

Tests: 60 in `test/` (Reception, settings, appearance, platforms, testing, availability timeout, exports), ported from the RN suites. Host→Dart calls
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
- `ReceptionPaywall` copies `products` into an unmodifiable list in its (non-const) constructor.
- Caller-owned data is copied at call time: paywall lists, metadata, and the push routing
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
  configure. While it waits, every tap (any key, any conversation) is recorded as opened and not routed, so the
  chat opens once, at the drain; receipts still route.
  `ReceptionNotificationCenter` proxy installed once at the first handling configure, wraps the previous delegate,
  handles Reception payloads (receipt → `[]` while chat open else `[.banner, .list, .sound]`; default-action tap →
  open; other actions only complete), forwards everything else through `OnceCompletion` (exactly once;
  fallback `[]` after 2 s for `willPresent`, logged once at info level because a wrapped firebase_messaging never
  answers notifications it no longer owns; `()` after 10 s for `didReceive`), forwards `openSettingsFor`. A later opt-out makes it pass-through and restores the previous
  delegate if it still owns the center; a replacement by someone else is logged once (info) and never re-wrapped.
- `NotificationRouting.swift` (RN state machine with exact-key dedupe, at most 64 keys, oldest evicted first, plus
  at most one pending tap; one chat per device, so every tap means "open the chat" and opening it while presented
  is a no-op), `OnceCompletion.swift`,
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
  `PaywallRequests` with `tool/native_tests/LogicTests.swift` (macOS, incl. the pending tap absorbing taps, exact-key
  dedupe after the drain, opt-out, latest capture, and late replies
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
- A duplicate delivery of the launch response that arrives after the drain and after the user has already closed
  the chat reopens it once (legacy path, key `"launch"` vs `identifier|date`; not observed in practice, duplicates
  arrive within the launch second).
- Distinct taps captured before configure keep only the latest.
- A tap routed while another screen is being presented does not open the chat (SDK presenter, see "Upstream SDK
  follow-ups").

Other changes after review: `welcomeIconOffset` components outside -1000…1000 are ignored (the SDK's appearance
report traps on huge values); calls to Dart queued for an earlier connection are skipped by a connection token;
a screen opened from a link card sends `onState`, then rechecks that token, the current connection and
cancellation before `onScreen`, so a reconnect during that await never lets a stale task navigate;
`example/ios/RunnerTests` imports the plugin module and tests `PushToken` and `NotificationRouting`
(`build-for-testing` succeeds; it needs any Flutter build of the example first to generate the SwiftPM package).
The connection-token check is one comparison inside `ReceptionHost`, which depends on Flutter and the SDK, so it has
no native unit test.

Open questions: none.

## Upstream SDK follow-ups (reception-ios)

Items 1 and 2 below are fixed in reception-ios 1.7.0, which the plugin vendors; items 3 and 4 remain open upstream.

To fix in the SDK and re-vendor with the next SDK release:
- `DeviceStore.clear()` omits the persisted `subscriptionStates` key, so stale dictionaries stay in UserDefaults after
  logout and deletion (`Vendor/Reception/Sources/Reception/Client/DeviceStore.swift:148`).
- German string for a failed image download says "Erneut senden" instead of "Erneut versuchen"
  (`Localizable.xcstrings` around line 7340, used by `RemoteAttachmentImage.swift:21`).
- A changed `appearance.preferredColorScheme` is not applied to an already presented chat (accent color and language
  do update), observed in the customer walkthrough.
- `ChatPresenter.present()` skips the chat while another screen is being presented (`Views/ChatPresenter.swift:48`,
  "another screen is being presented"), so a notification tap at that moment is dropped instead of presenting after
  the transition.

## Verification

Final simulator verification of the example app on the final plugin code: main at 12a01d3 (`Reception`-prefixed
types, opt-in `RECEPTION_SERVICE_URL`, cold-start taps opened 500 ms after configure with pending-tap duplicate
handling, plugin logic RunnerTests, Flutter minimum 3.44), 2026-10-28 13:29–14:02 CET, Flutter 3.47.8, Xcode 26.5,
iPhone 17 Pro / iOS 26.5, local backend on :3123. Exact commands, results and evidence: `verification/commands.txt`,
`verification/screenshots.txt`, `verification/*.log`; summary in German: `verification/EXPLAINER.md`. This
supersedes the earlier rounds (2026-10-27) and the notes above that the example is still the template and that
runtime behaviour is unverified.

Example: `example/lib/main.dart` exercises the whole public API (configure at startup when `RECEPTION_APP_ID` is
defined, against `RECEPTION_SERVICE_URL` when that is set, `RECEPTION_AUTOSTART=false` for the Configure button),
`example/integration_test/` drives it on a simulator, `example/ios/Runner/AppDelegate.swift` adds the example's own
notification-permission channel (`xcrun simctl privacy` has no notifications service), `Info.plist` declares
`en`/`de` localizations, and `Runner/Runner.entitlements` adds the Push Notifications entitlement.

All sections passed:
- a. analyze (root and example), format, 60 Dart tests, SDK sync check (107 files), native tests, pod lint with
  `LANG` unset, `flutter pub publish --dry-run` (207 KB, 0 warnings), RunnerTests `build-for-testing` and run
  (2 tests passed).
- b. integration test (1 test), clean SwiftPM build (0 warning lines), setup check, both previews.
- c. inbox reply → unread badge → reply in chat; identity and metadata in the inbox details; `hidden` absent from
  the Send offer dialog; offer card tap → `ReceptionPaywallOpened` and `onPaywall('plans')` with the chat still
  open; review card tap → `ReceptionReviewOpened` (iOS hands the App Store link to Safari on the simulator).
- d. simulator APNs token registered (sandbox); foreground banner with chat closed and unread refreshed by the
  receipt; no banner with chat open; background tap; cold-start tap opens the chat 0.67 s after configure with the
  example's purple appearance (after Dart settings); a second push for the same conversation tapped 24 s later opens
  the chat again in the running app.
- e. CocoaPods build, setup check and German strings from `Reception.bundle`; SwiftPM restored, no artifacts.
- f. hot restart under `flutter run`: unread and configuration re-read, availability (including the hanging
  callback failing closed and restoring) works.
- g. language override, dark/light, embedded view, deleteData (`ReceptionDataDeleted`, server data gone), logout
  (empty chat).
- h. fresh `flutter create` app: SwiftPM and CocoaPods builds after raising the deployment target to 17.0, no
  Podfile edits.

Final re-check after the routing simplification (193b2db: exact-key dedupe plus one pending tap, drained 500 ms after
configure) on main at 09fdaa7, 2026-10-28 14:11–14:19 CET: analyze (root and example), 60 Dart tests, native tests
(incl. pending tap), integration test, clean SwiftPM build, foreground banner with unread refresh, no banner with
the chat open, background tap, cold-start tap (chat 0.60 s after configure, purple appearance), a second push for
the same conversation tapped 26 s later (opens again), and hot restart with the availability check all pass
(`verification/commands.txt` "FINAL RE-CHECK AFTER ROUTING SIMPLIFICATION", `verification/recheck-*.log`).

Observed, not bugs: `flutter test integration_test` uninstalls the app afterwards (the next install is a new device
with a new conversation) and leaves its test-harness build in `example/build/ios/iphonesimulator/Runner.app`, which
shows a white screen when launched standalone; run it first or rebuild the example before installing it. In the
2026-10-27 rounds, `setPushToken` called before configure was cached and applied after configure (as PUSH-DESIGN
specifies), so the example's "Calls before configure" registered its dummy `aabb` token until the real token
replaced it. During this round the Mac's data volume ran full, which crashed one `flutter run` compiler and left the
simulator shut down; the affected steps were repeated after freeing space (see `verification/commands.txt`).

Physical device (2026-10-28, iPhone 16 Pro, iOS 27.2, Release build against the hosted service, see
`verification/commands.txt` "PHYSICAL DEVICE ROUND"): real APNs delivery from the backend, banner with chat closed,
no banner with chat open, background tap opens chat, cold-start tap opens chat — all passed as observed by the developer.
Production path (2026-10-29): a release-testing export signed "Apple Distribution" with `aps-environment=production`,
built with Xcode 27.1, installed via devicectl; the token registered as PRODUCTION with the hosted service, a dashboard
reply was delivered through api.push.apple.com and the banner tap opened the chat (developer-observed). Note for
maintainers: build the archive in an isolated checkout — a concurrent `flutter build` in the same `example/` rewrites
`ios/Flutter/Generated.xcconfig` and its dart-defines, which once produced an archive configured for the local test app.

Not verified: release builds beyond the device round above; the App Store review sheet itself (no App Store on the simulator); a server-side
`ReceptionIdentityRejected` (a malformed token is ignored locally by the SDK with "Identity token ignored, its user_id
could not be read"); automations reacting to `track`; photo sending; release builds; Android/web at runtime (unit
tests only); Flutter 3.44–3.46 at runtime (this round used 3.47.8).

Extended round (2026-10-29, main f701a02–9ec88e3, macOS 27.2; `verification/commands.txt` "EXTENDED ROUND",
screenshots 40–53, `verification/extended/`): server-side identity rejection (`ReceptionIdentityRejected` with
`identity_token_invalid`) and a correctly signed token (Verified in the dashboard), an `OPEN_CHAT` automation opened by
`track` in 2.8 s (and no reaction to an unmatched event), iPad sheet/embedded/dark, web and macOS builds as no-ops
with one notice, a packed copy (`git archive` minus `.pubignore`) in a fresh consumer with SwiftPM and CocoaPods (the
testing override's localhost literals are absent from the Release binary), and the sync checker failing on one
changed byte all pass. Firebase (firebase_messaging 17.0.1) and flutter_local_notifications 22.3.3 coexist: the
proxy wraps their delegates, FCM payloads reach `FirebaseMessaging.onMessage`, FLN's foreground notification is
delivered through FLN's own completion, Reception payloads are recognized. Not verified this round, because UI
automation was unavailable after the macOS update (XCUITest cannot attach until Xcode's first-launch setup is run
with admin rights; no Accessibility permission): photo sending, rate limits/length/photo-count limits, the keyboard
over the embedded chat, visible banners and taps in the coexistence apps. The signed archive/IPA is blocked by a
keychain prompt; an unsigned Release build carries the resource bundle with `PrivacyInfo.xcprivacy` and 48
localizations.

Extended round, part 2 (2026-10-29, Xcode 27.1, main a39c6da–d54b719; `verification/commands.txt` "EXTENDED ROUND,
PART 2", screenshots 54–70) closed those gaps: photo sending (five photos via the system picker, shown in the app and
the dashboard), the photo count (the picker and composer stop at five), the server's message rate limit (notice
above the composer, the held message is resent after the cooldown, sending resumes), the 4,000-character length
limit (Send disabled with a notice), the embedded chat with the software keyboard (composer above the keyboard,
`resizeToAvoidBottomInset` default true), and Firebase and flutter_local_notifications with full permission: banner
with the chat closed, no banner with the chat open, background tap opens the chat, FCM payloads still reach
`FirebaseMessaging.onMessage`, and FLN's foreground local notification still presents.

SDK 1.7 round (2026-10-31, reception_flutter 1.1.0 on main 0456cc3, Xcode 27.1; `verification/commands.txt` "SDK 1.7
ROUND", screenshots 71–88, `verification/v17/`): link cards (website in the Safari sheet over the chat and, with
`opensWebLinksInApp = false`, in the Safari app; App Store page and iOS Settings opened; mailto/tel fail on the
simulator and the dashboard shows "could not be opened"), screens (`settings`, `order` with value 123: the dashboard
lists them from the device report, the chat closes, the callbacks run with `isChatOpen` false and the example
navigates; still working after a hot restart), the in-chat push card (Continue → Allow registers the token and shows
the status line; `hidesPushStatus` hides it; No thanks removes the card and it stays gone after logout) with
remote appearance on, the push regression set, the integration test and `tool/release_check.sh` (all 12 steps, 69 Dart
tests) pass. Local backend: migrations applied and the dev server restarted on the 1.7 code; the push card needed
APNs credentials, so a throwaway key was connected for the test and removed afterwards.

### Bugs found during verification

1. `ios/reception_flutter/Sources/reception_flutter/ReceptionHost.swift:131` (`configure`): a malformed App ID
   returns before `Reception.configure`, so nothing is logged. Expected: the native SDK's diagnostic ("Configure
   refused a malformed App ID; copy it from your dashboard", as in a Swift app); actual: no log line at all and
   `isConfigured` unchanged. Reproduce: in a fresh app call `await Reception.configure(appId: 'app_YOUR_APP_ID')`
   and read the `com.reception.sdk` log (`verification/extended/packed-consumer-debug-*.log`). Keeping earlier
   configuration unchanged is intended; only the diagnostic is missing. **Fixed** the same day: `configure` now
   calls `Reception.configure` first (the SDK logs the refusal) and only then applies notification ownership for
   accepted IDs.

2. Push card and local-only styling (vendored SDK 1.7.0, upstream):
   `Vendor/Reception/Sources/Reception/ViewModel/ChatPushPrompt.swift` resolves the card's prompt as
   `reception.usesRemoteAppearance ? reception.appearanceConfiguration.activePushPrompt : nil`. Expected: with
   **Ask for push notifications** on, the card appears after the person's message, "with no code in your app"
   (docs/flutter.md, Push; CHANGELOG 1.0.0). Actual: an app that sets `Reception.usesRemoteAppearance = false` (the
   documented way to keep local-only styling, as the example does) never shows the card; the status line still
   appears once push is authorized. Reproduce: dashboard push prompt "Replies only" (needs APNs credentials), fresh
   install of the example, send a message → no card; the same build with `usesRemoteAppearance = true` shows it
   (`verification/81-push-card.png`). The dashboard setting is not an appearance option, so either the SDK should
   read it regardless of `usesRemoteAppearance`, or the docs must say the card needs remote appearance.

Earlier rounds: the two found in the first round (`meta` missing from `dependencies`; `tool/pod_lint.sh` failing
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

## Minimum version and pub score

Checked 2026-10-27 20:29–21:10 CET on main 13ca309 (package files identical at 4f18624), Xcode 26.5. SDKs: Flutter
3.38.0 (Dart 3.10.0-290.4.beta), 3.38.1 (Dart 3.10.0), 3.44.0 (Dart 3.12.0), stable 3.47.8 (Dart 3.13.7). Old SDKs
ran in throwaway clones with their own `XDG_CONFIG_HOME`, so the SwiftPM toggle never touched the stable config.
Builds are simulator builds only; nothing was installed or launched. Commands, logs and diffs are in
`verification/min-version/` (`commands.txt`, `sdk-versions.txt`).

Result at the time: the then declared minimum (`flutter: ">=3.38.0"`, `sdk: ^3.10.0`) does not hold. The real floor is Flutter
3.44.0 for SwiftPM apps, which is the default, and for plugin development. CocoaPods apps work from 3.38.1.

| Step | 3.38.0 | 3.38.1 | 3.44.0 |
|---|---|---|---|
| `pub get` plugin | fail (SDK) | fail (pigeon) | pass |
| `pub get` example | fail (SDK) | pass | pass |
| analyze plugin / example | – (pub get fails) | fail (pigeon) / pass | pass / pass |
| `flutter test` | – (pub get fails) | fail (pigeon) | pass (53) |
| analyze + test without pigeon (probe) | – | pass / pass (53) | – |
| example build, SwiftPM | – | **fail** | pass |
| example build, CocoaPods | – | pass (`Reception.bundle` with privacy manifest and 48 tables) | pass |
| fresh `flutter create` app (target 17.0), SwiftPM | fail (SDK) | **fail** | pass |
| `pub publish --dry-run` | fail (SDK) | fail (pigeon); 0 warnings without pigeon | pass, 0 warnings |

Incompatibilities:
1. `pubspec.yaml:16-17`: Flutter 3.38.0 ships Dart `3.10.0-290.4.beta`, a prerelease, so `^3.10.0` rejects it.
   Pub fails for the plugin and for any app that depends on it ("reception_flutter from path which requires SDK
   version ^3.10.0", `3380-fresh-pub-get.log`). 3.38.1 is the first release with Dart 3.10.0.
2. `pubspec.yaml:29` `pigeon: ^29.0.11` needs Dart `^3.11.0` (Flutter 3.41.0+). Pigeon 27.3.1 is the first release
   that needs 3.11, and 27.3.0 is the last that supports 3.10. On 3.38.x, `pub get`, `analyze`, `test` and
   `publish --dry-run` fail in the plugin root (`3381-pub-get-plugin.log`). This is a dev dependency, so apps that
   depend on the plugin are not affected (the example resolves).
3. `ios/reception_flutter/Package.swift:11,15` depend on the `FlutterFramework` package at `../FlutterFramework`.
   Flutter creates `.packages/FlutterFramework` only from 3.44.0 (it is in the plugin template from 3.44.0 on, not in
   3.41.0). On 3.38.1, with SwiftPM on, every app fails in xcodebuild: "Could not resolve package dependencies: the
   package at '…/ephemeral/Packages/.packages/FlutterFramework' cannot be accessed" (`3381-build-ios-spm.log`,
   `3381-fresh-build-ios-spm.log`). Removing both lines (probe only) makes the example and a fresh app build on 3.38.1.
   On stable, the example build then warns "Plugin reception_flutter has a Package.swift for ios but is missing a
   dependency on FlutterFramework"
   (`stable-probe-no-flutterframework-example-build-ios-spm.log`).
4. No others. With pigeon removed, the plugin analyzes clean on Dart 3.10.0 and all 53 tests pass, so the code uses
   no language feature newer than 3.10. The Pigeon 29 output (`lib/src/messages.g.dart`, `Messages.g.swift`) compiles
   on 3.38.1. `FlutterSceneLifeCycleDelegate` and `addSceneDelegate` exist in the 3.38.1 engine headers, and the
   plugin-facing declarations match 3.47.8. `UiKitView(viewType:)` (`lib/src/chat_view.dart:13`) compiles. The
   strict-concurrency CocoaPods build passes. `meta: ^1.16.0` resolves to Flutter's pinned 1.17.0.

Recommendation (applied in fbfda64: `sdk: ^3.12.0`, `flutter: ">=3.44.0"`, README "Requires Flutter 3.44+"): raise the minimum to what is verified. In `pubspec.yaml:16-17` use
`sdk: ^3.12.0` and `flutter: ">=3.44.0"`, use the same `sdk` in `example/pubspec.yaml:6`, and change `README.md:6`
to "Requires Flutter 3.44+ … Dart 3.12+". This matches PLAN.md ("Requirements: Flutter 3.44+") and the Flutter
template for SwiftPM plugins. Run analyze again after the bump, because it raises the language version from 3.10.
The alternative keeps CocoaPods and SwiftPM support from 3.38.1. It needs `flutter: ">=3.38.1"`, removing
`Package.swift:11,15` (stable then warns in the example build, and Flutter's plugin guide asks for the
dependency), and either pigeon `^27.3.0` (regenerate and re-verify) or a note that maintainers need Flutter 3.41+.

pub.dev score (pana 0.23.19, stable 3.47.8, `pana.log`): **160/160**, no points lost. Conventions 30/30,
documentation 20/20 (125/125 API elements documented, example present), platforms 20/20 (iOS, "Swift PM-ready"),
analysis 50/50, dependencies 40/40 (latest SDKs and `pub downgrade` lower bounds pass). The pubspec check is marked
`[~]` because pana could not reach three URLs. All three answer 404 today: `repository` and `issue_tracker`
(github.com/reception-sh/reception-flutter, `pubspec.yaml:5-6`) and `documentation` (reception.sh/docs/flutter,
`pubspec.yaml:7`). This costs no points now, but the repository and docs page must be public before publishing,
because pub.dev links to them and validates the repository.

API docs (`dart doc`, stable, `dart-doc.log`): 2 libraries (`reception_flutter.dart`, `testing.dart`), 0 warnings,
0 errors, no unresolved references or missing docs. `testing.dart` is a public library under `lib/`, so its API page
is published too. That is intended, because it is importable.

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

## Android and web builds

2026-10-29, on f701a02, Flutter 3.47.8, Android SDK from Homebrew (`openjdk@17`, `android-commandlinetools`,
no Android Studio or emulator). Evidence and exact commands: `verification/android/commands.txt`.

PASS. An app that depends on the plugin builds for Android and web; Flutter prints nothing about the missing
Android or web implementation (no error, no warning). It registers the plugin for iOS only, so Android's
`GeneratedPluginRegistrant` never references it.

- Example: `flutter build apk --debug` in `example/` fails only because the example has no `android/` runner
  (`Flutter failed to read file at ".../example/android/app/build.gradle"`). The committed example, exported with
  `git archive` and given an Android runner in /tmp, builds `app-debug.apk`.
- Fresh `flutter create` app calling `configure`, `openChat`, `unreadCount.value` and rendering
  `ReceptionChatView`: `flutter build apk --debug` and `flutter build web` pass (web: only Flutter's standard
  "Wasm dry run succeeded" note).
- Consumer widget test with `TargetPlatform.android`: calls complete, unread count 0, no Pigeon host call, the
  chat view renders a 0×0 `SizedBox`, one log line "[Reception] Support chat is available on iOS only.". The same
  test with `TargetPlatform.iOS` fails at the bridge, so the check is real.
