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
`ReceptionReviewOpened`, `ReceptionPaywallOpened`, `ReceptionDataDeleted`, `ReceptionIdentityRejected(error)`),
`ReceptionError(code, status)` (implements Exception; `bridge_error`/0 for unknown), `ReceptionPushEnvironment`,
`ReceptionLogLevel`, `ReceptionIdentity`. Files in `lib/src/`: `reception.dart`, `types.dart`, `appearance.dart`,
`state.dart`, `chat_view.dart`, `platform.dart` (support guard, warnings, callback error reporting), `errors.dart`,
plus the generated `messages.g.dart` and `sdk_version.dart`.

Behaviour (port of RN `methods.ts`, `Reception.ts`, `state.ts`, `callbacks.ts`):
- Unsupported platform (`kIsWeb || defaultTargetPlatform != TargetPlatform.iOS`): every call completes immediately,
  state stays at defaults, one `debugPrint('[Reception] Support chat is available on iOS only.')` per process; no
  `dart:io`. Never touch the host before the first real call.
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
