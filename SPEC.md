# reception_flutter – implementation spec (binding for all workers)

Read PLAN.md (design + review outcome) and PUSH-DESIGN.md first. The React Native wrapper in
`/Users/andi/Code/support/reception-react-native` is the behavioural reference: the Flutter plugin mirrors its
public API and semantics one to one (names adapted to Dart conventions). The native iOS SDK sources are vendored in
`ios/reception_flutter/Sources/reception_flutter/Vendor/Reception` and compiled into the plugin module: bridge code
uses SDK types directly, **no `import Reception`**. Never edit vendored files (hash-checked by
`dart run tool/sync_ios_sdk.dart --check`). Never edit generated files (`Messages.g.swift`, `lib/src/messages.g.dart`,
`test/messages_test.g.dart`); change `pigeons/reception.dart` and regenerate with
`dart run pigeon --input pigeons/reception.dart` only if the contract must change, and say so in your report.

Quality bar: simplest correct code, no dead code, no speculative abstractions, no TODOs, every public Dart member
documented (dartdoc), `flutter analyze` and `dart format` clean, Swift compiles without warnings under
Swift 6 tools / language mode 5 / strict concurrency complete. Do not add dependencies.

## Dart public API (lib/reception_flutter.dart)

```dart
class Reception {   // static-only facade, like RN's `Reception` object
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
  static void Function(ReceptionEvent event)? onEvent;        // setter/getter pair
  static void Function(String id)? onPaywall;                 // setter calls host setPaywallHandler(enabled)
  static FutureOr<bool> Function(String id)? paywallAvailability; // setter bumps generation, host setPaywallAvailability
}
class ReceptionChatView extends StatelessWidget {}  // UiKitView(viewType: 'reception_flutter/chat'); SizedBox.shrink() elsewhere
```
Every exported type carries the `Reception` prefix (generic names such as `LogLevel` clash with other plugins,
for example `purchases_flutter`). Types: `ReceptionAppearance` (immutable, all fields nullable, `copyWith`, `toJson` producing the RN JSON shape; fields and
validation ranges exactly as RN `types.ts`/`validation.ts`; invalid fields keep their previous value and warn),
`ReceptionColor` (`ReceptionColor.hex('#RRGGBB'|'#RRGGBBAA')` or `ReceptionColor.adaptive(light:, dark:)`, validated
hex), `ReceptionWelcomeIcon` (symbol | image | hidden), `ReceptionCloseIcon`, `ReceptionFontDesign`, `ReceptionColorScheme`, `ReceptionPaywall`,
`ReceptionPaywallProduct`, `ReceptionEvent` (sealed: chatOpened, messageSent, imageSent, reviewOpened, paywallOpened,
dataDeleted, identityRejected(error)), `ReceptionError(code, status)` (implements Exception; `bridge_error`/0 for
unknown), `ReceptionPushEnvironment`, `ReceptionLogLevel`, `ReceptionIdentity`. Keep the number of files small: `reception.dart`, `types.dart`,
`appearance.dart`, `state.dart`, `chat_view.dart`, `platform.dart` (support guard), `errors.dart`.

Behaviour (port of RN `methods.ts`, `Reception.ts`, `state.ts`, `callbacks.ts`):
- Unsupported platform (`kIsWeb || defaultTargetPlatform != TargetPlatform.iOS`): every call completes immediately,
  state stays at defaults, one `debugPrint('[Reception] Support chat is available on iOS only.')` per process; no
  `dart:io`. Also never touch the host before the first real call (lazy `connect()`).
- First host use calls `connect()` (hot restart replaces the previous connection natively) and installs the
  `ReceptionFlutterApi` implementation (`ReceptionFlutterApi.setUp`). Snapshots with a lower `revision` than the
  confirmed one are ignored. Settings use per-key assignment revisions exactly like RN `assignSetting`.
- Input validation like RN (`warnInvalid` → `debugPrint('[Reception] Invalid <field>; ignored.')`): appId string,
  metadata string values, push token `^([0-9a-f]{2})+$` case-insensitive ≤512 chars lowercased, event string,
  paywall shape, appearance fields.
- Errors from the host (`PlatformException`) become `ReceptionError.from(...)`; `deleteData` rethrows the typed error
  from `DeleteResultMessage.error`.
- `paywallAvailability`: host calls `checkPaywallAvailability(id, generation)`; Dart returns `false` for a stale
  generation, a missing callback, a thrown error (warn) or a non-`true` result. Never throw back to the host.
- `logout`/`deleteData` success: nothing push-specific in Dart (native re-applies the cached token).

Tests (`test/`): use the generated `TestReceptionHostApi` (`test/messages_test.g.dart`) with
`TestDefaultBinaryMessengerBinding`; cover: configure hydrates state; typed errors; identity/metadata/push validation
(the five bad tokens from RN); push payload recognition; track; settings optimistic update + reconciliation by
revision + rollback on host failure; paywall availability generation/stale/throwing; events mapping incl.
identityRejected; unsupported platform (override `debugDefaultTargetPlatformOverride`) never touches the messenger;
ReceptionChatView renders SizedBox.shrink off-iOS. Mirror RN `tests/*.test.ts` scope.

## iOS host (ios/reception_flutter/Sources/reception_flutter/)

Files: `ReceptionFlutterPlugin.swift` (registration, app/scene delegate), `ReceptionHost.swift` (implements
`ReceptionHostApi`; snapshot/revisions/connect/invalidate, port of RN `ReceptionBridge.swift` + `ReceptionModule.swift`),
`PaywallRequests.swift` (availability with 5 s fail-closed timeout and generation check, using
`ReceptionFlutterApi.checkPaywallAvailability`), `PaywallValues.swift`, `ReceptionAppearance.swift`,
`ReceptionColor.swift`, `PushToken.swift`, `NotificationRouting.swift` (bounded, 64 keys), `ReceptionNotifications.swift`
(token cache, notification-center proxy, cold-start queue; per PUSH-DESIGN.md as amended by review),
`ReceptionChatPlatformView.swift` (factory + view hosting `UIHostingController(rootView: ReceptionChatView())`, port of
RN `ReceptionNativeView.swift`). Logger subsystem `com.reception.flutter`.
- Single `ReceptionHost.shared` (MainActor) regardless of engines; `connect()` replaces the previous Dart connection
  (invalidate: cancel pending availability requests, clear onEvent/onPaywall, keep `paywallAvailability = { _ in false }`
  while an availability callback was set, bump observation token).
- Pigeon host methods run on the main thread: wrap bodies in `MainActor.assumeIsolated`; async ones use `await MainActor.run`.
- `configureForTesting` compiled under `#if DEBUG`, localhost-only guard as RN; in release return `snapshot()` unchanged.
- State publishing: `withObservationTracking` on the SDK's observable properties → `flutterApi.onState(snapshot)`.
- `version()` → `Reception.version`.

Build checks for the iOS worker: `cd example && flutter build ios --simulator --debug` with SwiftPM on (default) and
with `flutter config --no-enable-swift-package-manager` (CocoaPods), then `pod lib lint ios/reception_flutter.podspec
--allow-warnings=false --skip-tests` (note: `--use-modular-headers`), and `swiftc`-based unit tests for pure logic files
(PushToken, NotificationRouting, ReceptionColor, PaywallValues cannot without Flutter – skip) via `tool/test_native.sh`.
