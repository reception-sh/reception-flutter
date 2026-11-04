# reception_flutter – implementation spec (binding for all workers)

Read PLAN.md ("Final state") and PUSH-DESIGN.md ("Final decisions after review") first. The React Native wrapper in
`/Users/andi/Code/support/reception-react-native` is the behavioural reference: the Flutter plugin mirrors its
public API and semantics (names adapted to Dart conventions). The native iOS SDK sources are vendored in
`ios/reception_flutter/Sources/reception_flutter/Vendor/Reception` and compiled into the plugin module: bridge code
uses SDK types directly, **no `import Reception`**. Never edit vendored files (hash-checked by
`dart run tool/sync_ios_sdk.dart --check`). Never edit generated files (`Messages.g.swift`, `lib/src/messages.g.dart`,
`lib/src/sdk_version.dart`); change `pigeons/reception.dart` and regenerate with
`dart run pigeon --input pigeons/reception.dart && dart format lib/src/messages.g.dart` only if the contract must
change, and say so in your report.

Quality bar: simplest correct code, no dead code, no speculative abstractions, no TODOs, every public Dart member
documented (dartdoc), `flutter analyze` and `dart format` clean, Swift compiles without warnings under
Swift 6 tools / language mode 5 / strict concurrency complete. Do not add dependencies.

## Dart public API (lib/reception_flutter.dart, lib/testing.dart)

```dart
abstract final class Reception {   // static-only facade, like RN's `Reception` object
  static Future<void> configure({required String appId, bool handlesNotifications = true});
  static bool get isConfigured;                 // from the last native snapshot
  static String get version;                    // bundled iOS SDK version (lib/src/sdk_version.dart)
  static ValueListenable<int> get unreadCount;  // ValueNotifier mirrors of snapshot fields
  static ValueListenable<bool> get isChatOpen;
  static ValueListenable<List<ReceptionPaywall>> get availablePaywalls;
  static Future<void> openChat();  static Future<void> closeChat();
  static Future<void> identify(ReceptionIdentity identity);     // ReceptionIdentity.user(userId:, name:, email:) | ReceptionIdentity.token(token)
  static Future<void> setMetadata(Map<String, String> metadata);
  static Future<void> logout();
  static Future<void> deleteData();   // throws ReceptionError
  static Future<void> track(String event, {bool opensChat = false});
  static Future<void> setPushToken(String hexToken, {ReceptionPushEnvironment environment = ReceptionPushEnvironment.automatic});
  static Future<void> registerForPushIfAuthorized();
  static Future<bool> handlePushNotification(Map<String, Object?> payload, {bool openChat = true});
  static Future<void> refreshPaywalls({bool invalidate = false});
  // settings (immediately visible, reconciled by native revision like RN state.ts)
  static ReceptionAppearance get appearance; static set appearance(ReceptionAppearance value);
  static bool get updatesAppBadge; static set updatesAppBadge(bool value);
  static bool get usesRemoteAppearance; static set usesRemoteAppearance(bool value);
  static String? get languageOverride; static set languageOverride(String? value);
  static ReceptionLogLevel get logLevel; static set logLevel(ReceptionLogLevel value);
  static List<ReceptionPaywall> get paywalls; static set paywalls(List<ReceptionPaywall> value);
  static List<ReceptionScreen> get screens; static set screens(List<ReceptionScreen> value); // setter validates IDs, host setScreens([{id, value?}]); host onScreen(id, value) runs the matching callback
  // callbacks
  static void Function(ReceptionEvent event)? onEvent;            // Dart only; native always forwards events
  static void Function(String id)? onPaywall;                     // setter calls host setPaywallHandler(enabled)
  static FutureOr<bool> Function(String id)? paywallAvailability; // setter bumps generation, host setPaywallAvailability(enabled, generation)
}
class ReceptionChatView extends StatelessWidget {}  // UiKitView(viewType: 'reception_flutter/chat'); SizedBox.shrink() elsewhere
// package:reception_flutter/testing.dart
Future<void> configureReceptionForTesting({required String appId, required Uri serviceUrl});
```
Every exported type carries the `Reception` prefix (generic names such as `LogLevel` clash with other plugins,
for example `purchases_flutter`). Types: `ReceptionAppearance` (immutable, all fields nullable, `copyWith`, `toJson`
producing the RN JSON shape; fields and validation ranges exactly as RN `types.ts`/`validation.ts`; invalid fields
keep their previous value and warn), `ReceptionColor` (`ReceptionColor.hex('#RRGGBB'|'#RRGGBBAA')` or
`ReceptionColor.adaptive(light:, dark:)`, validated hex), `ReceptionWelcomeIcon` (symbol | image | hidden),
`ReceptionCloseIcon`, `ReceptionFontDesign`, `ReceptionColorScheme`, `ReceptionPaywall`, `ReceptionPaywallProduct`,
`ReceptionEvent` (sealed: `ReceptionChatOpened`, `ReceptionMessageSent`, `ReceptionImageSent`,
`ReceptionReviewOpened`, `ReceptionPaywallOpened`, `ReceptionLinkOpened`, `ReceptionDataDeleted`, `ReceptionIdentityRejected(error)`), `ReceptionScreen` (`ReceptionScreen(id, onOpen:)` | `ReceptionScreen.withValue(id, value:, onOpenWithValue:)`, `isValid` mirrors the SDK's ID rule),
`ReceptionError(code, status)` (implements Exception; `bridge_error`/0 for unknown), `ReceptionPushEnvironment`,
`ReceptionLogLevel`, `ReceptionIdentity`. Files in `lib/src/`: `reception.dart`, `types.dart`, `appearance.dart`,
`state.dart`, `chat_view.dart`, `platform.dart` (support guard, warnings, callback error reporting), `errors.dart`,
plus the generated `messages.g.dart` and `sdk_version.dart`.

Behaviour (port of RN `methods.ts`, `Reception.ts`, `state.ts`, `callbacks.ts`):
- Unsupported platform (web, or neither iOS nor Android): every call completes immediately, state stays at defaults,
  one `debugPrint('[Reception] Support chat is available on iOS and Android only.')` per process; no `dart:io`. Never
  touch the host before the first real call.
- First host use installs `ReceptionFlutterApi.setUp` and calls `connect()`, which hydrates state; concurrent callers
  share one attempt, a failed attempt is retried by the next call. Snapshots with a lower `revision` than the
  confirmed one are ignored. Settings use per-key assignment revisions exactly like RN `assignSetting`.
- Input validation like RN (`warnInvalid` → `debugPrint('[Reception] Invalid <field>; ignored.')`): metadata string
  values, push token `^([0-9a-f]{2})+$` case-insensitive ≤512 chars lowercased, paywall shape, appearance fields.
- Errors from the host (`PlatformException`) become `ReceptionError.from(...)`; `deleteData` rethrows the typed error
  from `DeleteResultMessage.error`. Fire-and-forget setter failures log `[Reception] Native bridge call failed.`
- `onEvent`/`onPaywall` handler exceptions are reported with `FlutterError.reportError`, never thrown to the host.
- `paywallAvailability` (request/resolve): native calls `requestPaywallAvailability(requestId, id, generation)`;
  Dart always answers with `resolvePaywallAvailability(requestId, allowed)`. `allowed` is false for a stale
  generation, a missing or since-replaced callback, a thrown error (reported), a result later than 5 s, or a
  non-`true` result. Native fails each request closed after 5 s, when the SDK cancels it, or when the callback or
  connection changes; late, duplicate and unknown answers are ignored.
- `logout`/`deleteData` success: nothing push-specific in Dart (native re-applies the cached token).

Tests (`test/`): `test/fake_host.dart` (`FakeHost`) answers every `ReceptionHostApi` channel on
`TestDefaultBinaryMessengerBinding`'s messenger and drives `ReceptionFlutterApi` calls; `resetReception()`
(`@visibleForTesting`) restores the initial Dart state between tests, as after a hot restart. Cover: configure
hydrates state; typed errors; identity/metadata/push validation (the five bad tokens from RN); push payload
recognition; track; settings optimistic update + reconciliation by revision + rollback on host failure; paywall
availability generation/stale/throwing/timeout; events mapping incl. identityRejected; unsupported platform
(`debugDefaultTargetPlatformOverride`) never touches the messenger; `ReceptionChatView` renders `SizedBox.shrink`
off-iOS; exports; testing entry point. Mirror RN `tests/*.test.ts` scope.

## iOS host (ios/reception_flutter/Sources/reception_flutter/)

Files: `ReceptionFlutterPlugin.swift` (registration, app and scene lifecycle delegate), `ReceptionHost.swift`
(implements `ReceptionHostApi`; snapshot/revisions/connect/invalidate, port of RN `ReceptionBridge.swift` +
`ReceptionModule.swift`), `PaywallRequests.swift` (request/resolve availability, 5 s fail-closed timeout),
`PaywallValues.swift`, `ReceptionAppearance.swift`, `ReceptionColor.swift`, `PushToken.swift`,
`NotificationRouting.swift` (bounded, 64 keys, launch-tap marker), `OnceCompletion.swift` (exactly-once completion
gate with fallback timer), `ReceptionNotifications.swift` (token cache, `ReceptionNotificationCenter` proxy, pending
launch tap; per PUSH-DESIGN.md final decisions), `ReceptionChatPlatformView.swift` (factory + view hosting
`UIHostingController(rootView: ReceptionChatView())`, port of RN `ReceptionNativeView.swift`), generated
`Messages.g.swift`. Logger subsystem `com.reception.flutter`.
- One `ReceptionHost` per engine, created in `register(with:)`; `detachFromEngine` tears down the channel and
  invalidates it. A static weak `current` marks the connected host: `connect()` invalidates the current one (another
  engine, or the same engine before a hot restart), becomes current, resets setting revisions, sets `onEvent` and
  starts observation. Only the current connection may change `onPaywall` and `paywallAvailability`.
- `invalidate()`: cancel pending availability requests (fail closed) and in-flight calls to Dart; if current, clear
  `onEvent`/`onPaywall` and keep `paywallAvailability = { _ in false }` while one was set.
- `ReceptionHost` is `@MainActor` with a `@preconcurrency ReceptionHostApi` conformance (Pigeon calls on the main
  thread); `@async` host methods complete from a `Task`.
- `configureForTesting` acts only in `#if DEBUG && targetEnvironment(simulator)` builds and only for `http`/`https`
  URLs on `localhost`, `127.0.0.1` or `::1`; otherwise it returns `snapshot()` unchanged.
- State publishing: `withObservationTracking` on the SDK's observable properties → `flutterApi.onState(snapshot)`.
- `version()` → `Reception.version`.

Build checks: `cd example && flutter build ios --simulator --debug` with SwiftPM on (default) and with
`flutter config --no-enable-swift-package-manager` (CocoaPods), `tool/pod_lint.sh` (both CocoaPods modes), and
`tool/test_native.sh` (swiftc unit tests: PushToken, NotificationRouting, OnceCompletion, PaywallRequests on macOS;
ReceptionColor in a simulator).

## Android host (android/src/main/kotlin/sh/reception/flutter/)

Added in 1.2.0. Wraps the Reception Android SDK (`sh.reception:reception`, `../reception-android/SPEC.md`) from Maven
Central; nothing is vendored. Kotlin, AGP and Kotlin versions from Flutter 3.47's plugin template, minSdk 24, no
Compose compiler (the plugin only calls SDK APIs). Same Pigeon contract; the Dart API is unchanged.

| Behaviour | iOS (Swift) | Android (Kotlin) |
| --- | --- | --- |
| Registration, lifecycle | `ReceptionFlutterPlugin.swift`: app and scene delegate (token, launch and scene taps, foreground re-registration) | `ReceptionFlutterPlugin.kt`: `FlutterPlugin` + `ActivityAware`; on every activity attach `Reception.noteCurrentActivity` (`@ReceptionInternalApi`), activity held weakly |
| Host API | `ReceptionHost.swift` | `ReceptionHost.kt`: same connect/invalidate, revisions, `isCurrent` guards; state from `unreadCount`/`isChatOpen` flows and `snapshotFlow { availablePaywalls }` (`SnapshotNotifications.kt` sends Compose apply notifications while no Compose UI runs); calls to Dart run in a per-connection coroutine scope cancelled by `invalidate` |
| `configureForTesting` | DEBUG simulator builds, `localhost`/`127.0.0.1`/`::1` | debuggable apps, those hosts plus `10.0.2.2` (the emulator's host loopback); the SDK checks debuggability again |
| Paywall availability | `PaywallRequests.swift` | `PaywallRequests.kt`: same rules (5 s fail-closed, SDK cancellation, `cancelAll`; late, duplicate, unknown answers ignored) |
| Paywall values | `PaywallValues.swift` | `PaywallValues.kt` |
| Appearance | `ReceptionAppearance.swift`; colors `ReceptionColor.swift` (dynamic `UIColor`); `fontFamily` must be registered with iOS; images from the asset catalog; symbols checked with `UIImage(systemName:)` | `ReceptionAppearance.kt`; colors `ReceptionColor.kt` (hex or `{light, dark}` decoded to ARGB ints and passed as the SDK's `ReceptionColor.argb(light, dark)`, so the SDK picks the variant for system, `preferredColorScheme` and remote appearance); `fontFamily` from Flutter's `FontManifest.json` built into a Compose `FontFamily` from the app's assets (`ReceptionAssets.kt`); images are drawable resources by name (`res/drawable`; Flutter assets are not supported): vector and bitmap files go to the SDK as resource ids (`WelcomeIcon.resource`, `closeImageResource`, drawn by the SDK at any density), other drawables (shapes, layer lists, `<bitmap>` XML), which `painterResource` cannot draw, are rasterized once at their intrinsic size and passed as a `Painter`; symbol names pass through (the SDK draws the dashboard's symbols and its built-in icon for others). A missing font or image keeps the previous value, as on iOS |
| Push token | `PushToken.swift` (APNs hex), cache in `ReceptionNotifications.swift` | `PushToken.kt` (FCM rule), cache in `ReceptionNotifications.kt`; the SDK fetches the token from Firebase itself |
| Notifications | `ReceptionNotifications.swift` proxy delegate, `NotificationRouting.swift`, `OnceCompletion.swift` | `ReceptionPushReceiver.kt` (c2dm `RECEIVE` beside Firebase and firebase_messaging); taps and routing belong to the SDK's trampoline activity, so there is no plugin routing; `configure` calls `Reception.setNotificationRoutingEnabled(handlesNotifications)` (`@ReceptionInternalApi`) before the SDK's `configure` (`configureForTesting`: true), so with `false` a pending cold-start tap is discarded and taps only bring the app forward; `handlesNotifications` is persisted for the receiver, which shows Reception messages only while it is true. See PUSH-DESIGN.md "Android" |
| Embedded chat | `ReceptionChatPlatformView.swift` (`UiKitView`) | `ReceptionChatPlatformView.kt` (Dart: `PlatformViewLink` with `initExpensiveAndroidView`, hybrid composition): the SDK's `ReceptionChatView` on its own `Recomposer`, composed until Flutter disposes the view (`DisposeOnLifecycleDestroyed` of the view's own lifecycle owner). Flutter keeps platform views when a cached engine outlives its activity, so `ChatActivity` (one per engine) moves every live chat to the activity the plugin is attached to (`onReattachedToActivityForConfigChanges`, a later `onAttachedToActivity`): the chat's context (a `MutableContextWrapper`) gets the new activity as its base and its lifecycle follows the new activity; the old activity's DESTROYED only stops the chat, and while detached the base is the application context. `OverlapInsets.kt` passes only the overlapping part of the window insets (keyboard avoidance as on iOS). `ActivityResults.kt` is the one `ActivityResultRegistry` of the engine's chats (photo picker, notification permission), kept across activities: launches go through the current activity's own registry when it has one (`FlutterFragmentActivity`, under `sh.reception.flutter.activity:<code>`/`permissions:<code>` keys that the next activity registers again, so a result that arrives after recreation is delivered) and otherwise with a request code whose result comes back through the plugin binding's listeners. Its state (`ActivityResultRegistry.onSaveInstanceState` plus the forwarded codes) and each chat's saved state (launcher keys from `rememberSaveable`) go into the activity's saved state and are restored, in creation order, by a plugin that starts after the process died |
| Native tests | `tool/native_tests` (swiftc) | `android/src/test` (JUnit): PaywallRequests, ReceptionColor, PushToken, FontManifest parsing; run from `example/android` with `./gradlew :reception_flutter:testDebugUnitTest` |
