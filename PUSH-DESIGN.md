# Push design for reception_flutter (iOS)

Verified facts (Flutter engine source, FlutterFire source, Flutter UIScene migration page, 2026-10-27):

- `FlutterPlugin` inherits `FlutterApplicationLifeCycleDelegate`, which inherits `UNUserNotificationCenterDelegate`. After `registrar.addApplicationDelegate(self)`, Flutter forwards to every responding plugin (in registration order, alphabetical by package name): `didRegisterForRemoteNotificationsWithDeviceToken`, `didFailToRegister…`, `userNotificationCenter(_:willPresent:withCompletionHandler:)`, `userNotificationCenter(_:didReceive:withCompletionHandler:)` (all plugins get the same completion block; Flutter never calls it), `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` (first plugin returning true stops propagation), `didFinishLaunchingWithOptions` (launchOptions nil under UIScene).
- `FlutterAppDelegate` does NOT set itself as `UNUserNotificationCenter.current().delegate`. In a plain Flutter app the center delegate is nil unless the app or a plugin sets it. Forwarding of `willPresent`/`didReceive` to plugins therefore only happens when something set the app delegate as the center delegate.
- `firebase_messaging` (FlutterFire) at its setup (didFinishLaunching notification, or at registration when scenes are already connected): if the center delegate is nil it sets itself; if a delegate exists that is not a `FlutterAppLifeCycleProvider`, it saves it as `_originalNotificationCenterDelegate`, sets itself, and forwards every `willPresent`/`didReceive` to the saved delegate (then does NOT call the completion handler; the original owns it). Payloads without `gcm.message_id` are never sent to Dart. Cold start: reads `launchOptions[remoteNotification]` (legacy) or `connectionOptions.notificationResponse` (scene).
- UIScene is default from Flutter 3.41 (APIs since 3.38). Plugins register from `scene:willConnectToSession:options:` after UIKit's `didFinishLaunching` returned; `launchOptions` are nil; `FlutterSceneLifeCycleDelegate.scene(_:willConnectTo:options:)` receives `connectionOptions` (nil if another plugin already handled it; `firebase_messaging` returns… unknown, so do not rely on receiving it when Firebase is present).
- Reception sends plain APNs alert pushes with `reception.conversationId`, no `gcm.message_id`, no `content-available`.
- SDK: `setPushToken` is ignored before `configure`; `logout()`/`deleteData()` clear the staged token; `handlePushNotification(userInfo:openChat:)` returns true only for Reception payloads; `registerForPushIfAuthorized()` never prompts.

## Design

### Token
1. Plugin implements `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`: stores `lastToken` in the plugin and forwards to `Reception.shared.setPushToken` when configured.
2. `configure` applies `lastToken` right after configuring. After `logout()` and successful `deleteData()`, Dart calls `registerForPushIfAuthorized()` again (it re-requests a token from APNs, which calls back the delegate; iOS returns the same token quickly). The plugin additionally re-applies `lastToken` immediately after those two calls so there is no gap.
3. Dart `Reception.setPushToken(hex, environment)` for apps that get the token elsewhere (e.g. Firebase `getAPNSToken()`); validated as APNs hex (even length, 2–512 hex chars) like RN; FCM tokens are rejected with a warning.
4. Dart `Reception.registerForPushIfAuthorized()` → SDK. The plugin also calls it on `sceneDidBecomeActive`/`applicationDidBecomeActive` when configured (same as the SDK recommends: launch, foreground). Never prompts.

### Receipt and taps — one native component, `ReceptionNotificationCenter`
Installed at `configure` (main thread) when `handlesNotifications` is true (default true):
- `previous = UNUserNotificationCenter.current().delegate`. If `previous` is already our proxy → no-op. Set `center.delegate = proxy`. Install exactly once per process (never re-wrap later; avoids cycles when another plugin wraps us as its "original").
- `willPresent`: Reception payload → `handlePushNotification(userInfo, openChat: false)`; complete with `[]` while `isChatOpen`, else `[.banner, .list, .sound]`; do not forward. Other payload → forward to `previous` if it responds; else complete with `[]` (iOS's no-delegate behaviour).
- `didReceive response`: Reception payload → route via `NotificationRouting` (key: `request.identifier`), `openChat: true` for the default action, ignore dismiss/custom actions; complete; do not forward. Other → forward to `previous` if it responds; else complete.
- `openSettingsFor` → forward only.
- When `previous` is nil and the app delegate is a `FlutterAppLifeCycleProvider` (plain Flutter app), we still install the proxy (not the app delegate), so behaviour is identical regardless of the app's AppDelegate.
- Documented order: Reception is configured from Dart after `runApp`, i.e. after Firebase/FLN set their delegates at launch; the proxy becomes the outermost delegate and preserves theirs.

### Cold start
- Legacy path: plugin `application(_:didFinishLaunchingWithOptions:)` reads `launchOptions[.remoteNotification]`; if Reception payload → enqueue `pendingTap` (keyed by a hash of the payload) and return true? No: return value `false`… Flutter stops the loop on the FIRST plugin returning **false** for the launch callbacks; return `true` always.
- Scene path: `registrar.addSceneDelegate(self)`; `scene(_:willConnectTo:options:)` reads `connectionOptions?.notificationResponse` (Reception payload → enqueue `pendingTap` keyed by `request.identifier`; return false so other plugins still get it).
- Also: the proxy, if installed, receives the launch tap via `didReceive` after launch → same key → deduped by `NotificationRouting`.
- Fallback for apps where no center delegate exists at launch and the OS used `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` for a tap: handle Reception payloads (`applicationState != .active` → tap, else receipt), key by payload hash, call completion `.noData`, return true; return false for other payloads.
- `configure` drains `pendingTap` once (opens chat) after applying settings; taps older than 60 s at drain time are still honoured (user intent), but the queue holds at most one tap (latest wins).

### Hot restart
`NotificationRouting` and `pendingTap` live in the native plugin singleton. Dart re-`connect()`s after a restart and receives a snapshot; no notification is replayed to Dart because routing is native-only. Bounded: `NotificationRouting` keeps the last 64 keys.

### Opt-out / manual
`configure(handlesNotifications: false)`: no proxy, no fallback routing. The app forwards payloads itself with `Reception.handlePushNotification(payload, openChat:)` (Dart) from its own native delegate bridge, and decides presentation with `Reception.isChatOpen`. Documented for apps that must own the center delegate (e.g. custom notification categories).

### What Firebase apps must do
Nothing beyond configuring Reception after `Firebase.initializeApp()`; their `onMessage`/`onMessageOpenedApp` keep working for FCM; Reception notifications never reach Dart Firebase handlers (no `gcm.message_id`), and are handled natively by the proxy. If they take the token via Firebase (`getAPNSToken`), they may call `Reception.setPushToken`, but the plugin's own lifecycle capture already covers it.

## Open questions for review
1. Any case where calling the completion handler ourselves for Reception payloads while another delegate also receives the same call (Flutter forwarding to all plugins when the app delegate is the center delegate) leads to a double completion? Mitigation: we only act on the call path we own: if `center.delegate === proxy`, we handle in the proxy and NOT in the FlutterPlugin forwarding method (the plugin's `userNotificationCenter…` implementations are omitted entirely; only the proxy implements them). Is that sufficient?
2. Any risk in reading `connectionOptions.notificationResponse` when Firebase is present (it may have consumed it)? Mitigation: the proxy is not installed at launch, Firebase forwards non-gcm taps to its saved original only if one existed at its setup time; at cold start that is nil. So with Firebase present, a cold-start Reception tap arrives only via `connectionOptions.notificationResponse` (scene) or `launchOptions` (legacy). Is `connectionOptions` nil for later plugins when Firebase returns true from `scene:willConnectToSession:options:`?
3. Should the proxy be installed at plugin registration time instead of at configure (so it exists at launch and before Firebase's setup)? Trade-off: then Firebase would wrap us as its original and forward everything to us, and we'd have to complete non-Reception notifications for Firebase with `[]`, overriding the app's `setForegroundNotificationPresentationOptions`. Configure-time install seems cleaner, but confirm.

---

## Final decisions after review (Codex gpt-6-astra xhigh, 2026-10-27) — binding for implementation

Corrections to the facts above: plugin callback order is delegate insertion order (dependency-ordered registration,
alphabetical tie-break), not simply alphabetical. Under UIScene, UIKit passes nil launch options; Flutter's launch
fallback passes an empty dictionary. Without any notification-center delegate iOS does not present foreground
notifications (equivalent to completing with `[]`).

### Token
- Plugin captures `didRegisterForRemoteNotificationsWithDeviceToken` → `cachedToken = (data, .automatic)`; Dart
  `setPushToken(hex, environment)` → `cachedToken = (data, environment)`. Whenever configured, apply immediately via
  `Reception.shared.setPushToken`.
- `configure` (and `configureForTesting`): after configuring, apply `cachedToken` if any, then call
  `await Reception.shared.registerForPushIfAuthorized()` (never prompts; authorized, provisional and ephemeral).
- Re-apply `cachedToken` after `logout()` and after successful `deleteData()`, then call `registerForPushIfAuthorized()`
  again. No assumption that APNs returns a token quickly; the cache covers the gap.
- Foreground: plugin's `sceneDidBecomeActive`/`applicationDidBecomeActive` → if configured, `registerForPushIfAuthorized()`.
- Dart `registerForPushIfAuthorized()` remains available for the app's own permission flow.

### Receipt and taps: `ReceptionNotificationCenter` proxy
- Installed once per process at the first `configure(handlesNotifications: true)` on the main actor; strongly retained
  by the plugin singleton. `previous = center.delegate` (may be nil, an app delegate, Firebase, FLN, …).
  If `center.delegate` is later replaced by someone else, log once at info level and do nothing (never rewrap).
- The `FlutterPlugin` class implements **no** `userNotificationCenter…` selectors; only the proxy does, so Flutter's
  forwarding to all plugins can never double-complete a Reception notification.
- Every forwarded completion handler is wrapped in an exactly-once gate (`OnceCompletion`): the first call wins, later
  calls are ignored; a fallback timer completes with `[]` after 2 s (willPresent) or `()` after 10 s (didReceive) if
  nobody did, logging once at info level. The gate runs on the main actor.
- `willPresent`: Reception payload → `handlePushNotification(userInfo, openChat: false)` routed through
  `NotificationRouting` (receipt), complete `[]` while `isChatOpen`, else `[.banner, .list, .sound]`; never forwarded.
  Otherwise forward to `previous` if it implements the selector; if no previous delegate, complete `[]` (preserves the
  app's behaviour before Reception: iOS showed nothing in the foreground without a delegate).
- `didReceive response`: Reception payload and `actionIdentifier == UNNotificationDefaultActionIdentifier` → route as
  tap (`openChat: true` or `.open` per routing state); dismiss/custom actions → route nothing but still complete; never
  forwarded. Otherwise forward to `previous` if it implements the selector; else complete.
- `openSettingsFor` → forward only when implemented by previous.
- Everything on the main actor; the proxy is `@MainActor final class … : NSObject, UNUserNotificationCenterDelegate`
  using the completion-handler variants only (never the async variants).

### Cold start and background taps
- Scene path (Flutter ≥ 3.38, default ≥ 3.41): `registrar.addSceneDelegate(plugin)`;
  `scene(_:willConnectTo:options:)` reads `connectionOptions?.notificationResponse`; Reception payload with the default
  action → `pendingTap = (key, conversationId)`; return `false` (never consume for others).
- Legacy path: `application(_:didFinishLaunchingWithOptions:)` reads `launchOptions?[.remoteNotification]`; Reception
  payload → `pendingTap` keyed by a one-launch alias `"launch"`; return `true` always.
- Running/background taps arrive through the proxy's `didReceive` (key `identifier + date`).
- `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` is **receipt only** (never a tap): Reception
  payload → `handlePushNotification(openChat: false)` (routing state: receive), complete `.noData`, return `true`;
  otherwise return `false`. Only used when `handlesNotifications` is on.
- `pendingTap` holds the latest tap until `configure(handlesNotifications: true)` succeeds, which drains it once (opens
  chat via routing). Opting out at first configure discards it. Keys consumed by a drain are recorded in routing so the
  same response arriving later via the proxy is ignored.

### Routing state (`NotificationRouting`)
- Port of RN: per key `receive` / `receiveAndOpen` / `open` / `ignore`; foreground receipts feed the same machine so
  receipt-then-tap yields `open`, not a second receive-and-open.
- Deterministic bound: ordered dictionary of at most 64 keys, oldest evicted first. Pending tap storage is separate.

### Opt-out (`handlesNotifications: false`)
- Gates launch capture, scene capture, pending-tap draining, fetch handling and proxy installation.
- If a proxy is already installed from an earlier configure and a later configure opts out: the proxy becomes
  pass-through (forwards everything, handles nothing); if the plugin still owns `center.delegate`, restore `previous`.
  Never overwrite a newer delegate.
- Apps then call `Reception.handlePushNotification(payload, openChat:)` from their own bridge; `Reception.isChatOpen`
  drives their presentation policy.

### Compatibility statements for the docs
- firebase_messaging ≥ 17.0.0 for apps that use Firebase (older versions complete unrelated notifications and
  mis-implement the scene callback). Configure Reception after `Firebase.initializeApp()`.
- flutter_local_notifications: keep its documented AppDelegate setup; Reception wraps whatever delegate exists at configure.
- Flutter ≥ 3.38 (scene delegate API). Verified on current stable 3.47.
