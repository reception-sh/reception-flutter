# Reception Flutter SDK (iOS) – Proposed Plan for Review

Context: Reception is a native in-app support chat. Existing repos in /Users/andi/Code/support:
- reception-ios: native Swift SDK (SwiftPM + Reception.podspec, iOS 17+, Xcode 26, swift-tools 6.0, StrictConcurrency, language mode 5). NOT published on CocoaPods Trunk.
- reception-react-native: Expo Module wrapper. Vendors the iOS SDK sources into vendor/reception-ios via scripts/sync-ios-sdk (hash-pinned in vendor/ios-sdk.json). Android/web are no-op stubs with a one-time warning. Push via expo-notifications helper; native NotificationRouting prevents double delivery across JS reloads.
- reception: backend/dashboard (Next.js), docs under reception/content/docs.

Goal: a Flutter plugin `reception_flutter` (iOS only for now, Android maybe later) with the same API surface as the RN package, published on pub.dev, "official standard" quality, built like Superwall/RevenueCat/Adapty.

## Research findings (Superwall, RevenueCat, Adapty Flutter plugins)
- All use the official Flutter plugin layout: lib/ (Dart), ios/<plugin>.podspec + ios/<plugin>/Package.swift pointing at the same Sources dir. Flutter 3.44+ uses SwiftPM by default; Flutter asks plugins to support BOTH SwiftPM and CocoaPods. CocoaPods Trunk becomes read-only on 2026-12-02.
- All three consume their native iOS SDK as a REMOTE dependency, pinned exact (Superwall-iOS 4.17.0, PurchasesHybridCommon 19.16.1, AdaptySDK-iOS 4.1.3), identical in podspec and Package.swift.
- Superwall uses Pigeon (single pigeons/configure.dart). Adapty uses a JSON cross-platform schema. RevenueCat uses MethodChannels in ObjC via a hybrid-common layer.
- Adapty/RevenueCat UI ship paywall views as Flutter PlatformViews (UiKitView).
- Intercom's Flutter plugin: app fetches APNs token (usually via firebase_messaging) and passes it to the SDK; plugin never owns push registration.

## Proposed design

Pre-review proposal; where it differs from the review outcome or "Final state" below, those win.

1. Repo `reception-flutter`, package `reception_flutter`. pubspec declares only ios platform. Dart guard: on non-iOS, calls no-op + warn once (same as RN).
2. Bridge: Pigeon, one definition file `pigeons/reception.dart` generating Dart + Swift (Kotlin later). Generated files committed.
3. Native SDK consumption: VENDOR the iOS SDK sources INTO the plugin target (ios/reception_flutter/Sources/reception_flutter/Vendor/Reception/...), compiled into the plugin module itself (not a nested package, not a remote dependency). One Package.swift and one podspec describe the same files. Reasons:
   - No CocoaPods Trunk needed (Trunk freezes Dec 2026 → remote-pod approach would freeze the version for CocoaPods users).
   - Flutter auto-links only ios/<plugin>.podspec per plugin, so a second vendored podspec (RN/Expo style) is not possible on the CocoaPods path.
   - A nested local SwiftPM package would only work on the SwiftPM path → two divergent build graphs.
   - No module-name collision if an app also adds reception-ios directly.
   - SDK's ReceptionResources.swift already resolves resources via Bundle.module under SWIFT_PACKAGE and via a resource bundle named "Reception" under CocoaPods; plugin declares both.
   - Sync script + hash manifest copied from the RN repo; prepublish check verifies hashes; Dart exposes sdkVersion.
4. Embedded chat: Flutter PlatformView (UiKitView) reusing the UIKit hosting code from RN's ReceptionNativeView.swift (UIHostingController attached to nearest VC).
5. Push:
   - Token: automatic via FlutterPlugin application lifecycle delegate (didRegisterForRemoteNotificationsWithDeviceToken is forwarded by FlutterAppDelegate to all plugins) + explicit Dart `registerPushToken(hex)` for apps using firebase_messaging. Both call the SDK's setPushToken. SDK never requests permission; `registerPushIfAuthorized()` exposed to Dart.
   - Cold-start tap via launchOptions in didFinishLaunchingWithOptions (forwarded to plugins).
   - Foreground + tap at runtime: plugin does NOT take over UNUserNotificationCenter.delegate by default (firebase_messaging usually owns it). Dart helpers `isReceptionNotification(payload)` and `handleNotification(payload, opened:)` to call from the app's existing handlers. Opt-in `handlesNotifications: true` sets the delegate only if none is set, otherwise warns.
   - Reuse NotificationRouting (dedupe across hot restarts).
6. Hot restart: native singleton persists; SDK already ignores repeated configure with same appId; Dart re-fetches native state and re-subscribes to the event stream on configure.
7. Requirements: Flutter 3.44+, iOS 17, Xcode 26. Plugin platforms .iOS("17.0"); podspec deployment_target 17.0. Clear docs + agent setup prompt (dashboard "Copy setup prompt") like RN.
8. Package.swift: swift-tools 6.0, swiftLanguageModes [.v5], StrictConcurrency complete (mirrors the SDK; Adapty does the same in production).
9. Verification: Dart unit tests with mocked Pigeon host; Swift tests via swiftc; example app in Simulator against real backend; build with SwiftPM on and off; pod lib lint; flutter pub publish --dry-run; simulator push via .apns payload file (foreground, background tap, cold start); screenshots in verification/.
10. Android later: Kotlin SDK as separate project; then add android/ folder to BOTH Flutter and RN packages, no new packages.

## Rejected alternatives
- Remote SwiftPM + CocoaPods Trunk (Superwall style): Trunk freeze.
- Nested local Swift package by path: SwiftPM-only, CocoaPods path breaks.
- Rewrite chat in Dart: double implementation, loses native UI.
- Docs-only manual integration: nobody would use it.

## Questions for the reviewer
1. Is vendoring the SDK sources into the plugin module really the cleanest, most bulletproof option for both SwiftPM and CocoaPods? Any edge case we miss (resource bundles, privacy manifest, Bundle.module under CocoaPods, use_frameworks! static vs dynamic, module name "Reception" vs "reception_flutter", @_spi usage, Swift 6 tools-version in a Flutter plugin, Pigeon generated code in the same module as the SDK)?
2. Is Pigeon the right bridge vs MethodChannel? Any Pigeon pitfalls (event streams, PlatformView args, hot restart)?
3. Push design: is the lifecycle-delegate token capture reliable when firebase_messaging swizzles the AppDelegate? Is "passive by default + opt-in delegate takeover" the right call? Anything about cold-start taps with Flutter we overlook?
4. Anything about Flutter 3.44+/SwiftPM default, iOS 17 minimum, Xcode 26 that would exclude a meaningful group of Flutter developers?
5. Anything else that would make this not "the best official-standard way"? Keep the answer concrete and compact: confirm / change / add, with reasons.

---

## Review outcome (Codex gpt-6-astra, 2026-10-27) and resulting changes

Confirmed: vendoring into one plugin target, Pigeon, PlatformView on the RN hosting code, iOS 17 / Xcode 26, Android later.

Changes adopted:

1. **No coexistence claim.** Docs state: never add the native `reception-ios` package to a Flutter app in addition to the plugin (two `Reception.shared` instances would share Keychain/UserDefaults storage).
2. **Packaging spec.** Package.swift: `defaultLocalization: "en"`, resources `.process("Vendor/Reception/Sources/Reception/Resources")` (Localizable.xcstrings + PrivacyInfo.xcprivacy), `FlutterFramework` path dependency, product `reception-flutter`, target `reception_flutter`, swift-tools 6.0, `swiftLanguageModes: [.v5]`, `.enableExperimentalFeature("StrictConcurrency")`. Podspec: same sources, `resource_bundles = { 'Reception' => [...] }` so `ReceptionResources` resolves on CocoaPods, `DEFINES_MODULE`, deployment target 17.0. Verify resource lookup under CocoaPods static and dynamic (`use_frameworks!` default and `:linkage => :static`) and under SwiftPM. Pigeon types use a `Message` suffix and the error class is `ReceptionBridgeError`, so nothing clashes with SDK types.
3. **Hot-restart protocol** (port of RN `ReceptionBridge.connect/invalidate`): Dart calls `connect()` on first use; native replaces the previous connection, cancels pending paywall availability requests (fail closed), clears `onEvent`/`onPaywall`, keeps `paywallAvailability = { _ in false }` while disconnected, and returns a revisioned snapshot. Settings carry assignment revisions; stale replies are ignored. Five-second fail-closed availability timeout preserved.
4. **Push token capture.** Plugin registers `registrar.addApplicationDelegate(self)`; `didRegisterForRemoteNotificationsWithDeviceToken` stores the raw token in the plugin and forwards it to the SDK. Tokens that arrive before `configure` are cached in the plugin and applied right after configure; the cached token is re-applied after `logout()` and successful `deleteData()` (SDK clears its staged token). Dart `setPushToken(hex)` accepts an APNs hex token only (validated like RN), never an FCM token.
5. **Native notification forwarding.** FlutterFire filters `onMessage`/`onMessageOpenedApp` by `gcm.message_id`, so Dart-side Firebase handlers never see direct-APNs Reception notifications. The plugin therefore handles notifications natively:
   - `didReceiveRemoteNotification` (plugin lifecycle callback) → foreground receipt with `openChat: false` when it carries `reception.conversationId` (only with `handlesNotifications`).
   - Notification taps: with `configure(handlesNotifications: true)` (default) the plugin installs a proxy `UNUserNotificationCenterDelegate` once, wrapping the delegate set at that time (Firebase and flutter_local_notifications set theirs at app launch, before Dart runs). Reception notifications are handled by the proxy and never forwarded (presentation: hide banner while chat open; tap opens chat); everything else is forwarded to the wrapped delegate. If another delegate replaces the proxy later, a later configure logs that once; the plugin never rewraps. Apps that want full ownership pass `handlesNotifications: false` and call `Reception.handlePushNotification(payload, openChat:)` from their own delegate.
   - Cold start: taps are queued natively until Dart has called `configure`; the latest tap is drained once, keyed by notification request identifier + date (scene path) or a `launch` alias (legacy launch options), through the bounded `NotificationRouting` (64 keys). Details in PUSH-DESIGN.md.
6. **Minimum Flutter version**: Flutter ≥ 3.44 (Dart ≥ 3.12): SwiftPM plugins depend on the `FlutterFramework` package Flutter creates from 3.44, and the scene lifecycle delegate is required. Verified on 3.44.0 and current stable.
7. **Unsupported platforms**: Dart guard uses `defaultTargetPlatform`/`kIsWeb` (web-compilable, no unconditional `dart:io`); widgets render `SizedBox.shrink()` and listenables keep defaults; one warning per process.
8. **Assets**: `closeImage`/`welcomeIcon.image` reference iOS asset-catalog names (same as RN) and the docs say so; Flutter asset keys are not resolved. `fontFamily` must be a font registered with iOS (pubspec fonts are registered by Flutter at runtime only for Flutter text, not UIKit), documented.
9. **Verification adds**: release archive inspection for resources/privacy manifest on both dependency managers; example-host integration tests; physical-device push and Firebase coexistence remain user-run.

## Final state (adopted)

- SDK sources vendored into the single `reception_flutter` target; `Package.swift` and the podspec compile the same
  sources and resources (`Localizable.xcstrings`, `PrivacyInfo.xcprivacy`); pinned by `vendor/ios-sdk.json` and
  `tool/sync_ios_sdk.dart`.
- Pigeon 29 contract in `pigeons/reception.dart`; paywall availability is request/resolve
  (`requestPaywallAvailability` → `resolvePaywallAvailability`) with a 5 s fail-closed timeout on both sides.
- One `ReceptionHost` per engine; the latest `connect()` wins (static current connection), the previous one is
  invalidated. Settings and snapshots are revisioned as in RN.
- Native push per PUSH-DESIGN.md "Final decisions": token cache and re-registration, proxy delegate, launch and scene
  tap capture, receipt-only fetch callback.
- Embedded chat as a `UiKitView` platform view; static `Reception` facade; all exported types `Reception`-prefixed;
  `package:reception_flutter/testing.dart` for localhost configuration (DEBUG simulator builds only).
- Requirements: Flutter ≥ 3.44, Dart ≥ 3.12, iOS 17, Xcode 26. Checks: `flutter test`, `tool/test_native.sh`,
  `tool/pod_lint.sh`, example builds with SwiftPM on and off.
