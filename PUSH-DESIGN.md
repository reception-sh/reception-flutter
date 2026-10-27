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
