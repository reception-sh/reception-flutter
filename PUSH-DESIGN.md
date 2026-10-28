# Push design for reception_flutter (iOS)

Verified facts (Flutter engine source, FlutterFire source, Flutter UIScene migration page, 2026-10-27):

- `FlutterPlugin` inherits `FlutterApplicationLifeCycleDelegate`, which inherits `UNUserNotificationCenterDelegate`. After `registrar.addApplicationDelegate(self)`, Flutter forwards to every responding plugin (in registration order, alphabetical by package name): `didRegisterForRemoteNotificationsWithDeviceToken`, `didFailToRegister…`, `userNotificationCenter(_:willPresent:withCompletionHandler:)`, `userNotificationCenter(_:didReceive:withCompletionHandler:)` (all plugins get the same completion block; Flutter never calls it), `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` (first plugin returning true stops propagation), `didFinishLaunchingWithOptions` (launchOptions nil under UIScene).
- `FlutterAppDelegate` does NOT set itself as `UNUserNotificationCenter.current().delegate`. In a plain Flutter app the center delegate is nil unless the app or a plugin sets it. Forwarding of `willPresent`/`didReceive` to plugins therefore only happens when something set the app delegate as the center delegate.
- `firebase_messaging` (FlutterFire) at its setup (didFinishLaunching notification, or at registration when scenes are already connected): if the center delegate is nil it sets itself; if a delegate exists that is not a `FlutterAppLifeCycleProvider`, it saves it as `_originalNotificationCenterDelegate`, sets itself, and forwards every `willPresent`/`didReceive` to the saved delegate (then does NOT call the completion handler; the original owns it). Payloads without `gcm.message_id` are never sent to Dart. Cold start: reads `launchOptions[remoteNotification]` (legacy) or `connectionOptions.notificationResponse` (scene).
- UIScene is default from Flutter 3.41 (APIs since 3.38). Plugins register from `scene:willConnectToSession:options:` after UIKit's `didFinishLaunching` returned; `launchOptions` are nil; `FlutterSceneLifeCycleDelegate.scene(_:willConnectTo:options:)` receives `connectionOptions` (nil if another plugin already handled it; `firebase_messaging` returns… unknown, so do not rely on receiving it when Firebase is present).
- Reception sends plain APNs alert pushes with `reception.conversationId`, no `gcm.message_id`, no `content-available`.
- SDK: `setPushToken` is ignored before `configure`; `logout()`/`deleteData()` clear the staged token; `handlePushNotification(userInfo:openChat:)` returns true only for Reception payloads; `registerForPushIfAuthorized()` never prompts.

## Draft design (superseded)

> Pre-review draft, kept as review context only. "Final decisions after review" below is binding and replaces
> this section and the open questions. In particular: token re-registration is native (Dart does nothing after
> `logout`/`deleteData`), and Reception may be configured before `runApp` (the README does).

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

## Open questions for review (answered in the final decisions)
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
- Plugin captures `didRegisterForRemoteNotificationsWithDeviceToken` → cached `(data, .automatic)`; Dart
  `setPushToken(hex, environment)` → cached `(data, environment)`. Whenever configured, apply immediately via
  `Reception.shared.setPushToken`.
- Every successful `configure` (and `configureForTesting`): apply the cached token if any, then start
  `Reception.shared.registerForPushIfAuthorized()` (never prompts; authorized, provisional and ephemeral).
- After `logout()` and successful `deleteData()` native re-applies the cached token and calls
  `registerForPushIfAuthorized()` again; Dart does nothing push-specific. The cache covers the APNs round trip.
- Foreground: plugin's `sceneDidBecomeActive`/`applicationDidBecomeActive` → if configured, `registerForPushIfAuthorized()`.
- Dart `registerForPushIfAuthorized()` remains available for the app's own permission flow.

### Receipt and taps: `ReceptionNotificationCenter` proxy
- Installed at the first `configure(handlesNotifications: true)` on the main actor; retained by
  `ReceptionNotifications.shared`. `previous = center.delegate` (may be nil, an app delegate, Firebase, FLN, …).
  If a later configure finds `center.delegate` replaced by someone else, it logs once at info level and does nothing
  (never rewraps).
- The `FlutterPlugin` class implements **no** `userNotificationCenter…` selectors; only the proxy does, so Flutter's
  forwarding to all plugins can never double-complete a Reception notification.
- Every forwarded completion handler is wrapped in an exactly-once gate (`OnceCompletion`, main actor): the first
  call wins, later calls are ignored; a fallback completes with `[]` after 2 s (`willPresent`, logged once at info
  level) or `()` after 10 s (`didReceive`) if the wrapped delegate never did.
- `willPresent`: Reception payload → receipt routed through `NotificationRouting` (`openChat: false`), complete `[]`
  while `isChatOpen`, else `[.banner, .list, .sound]`; never forwarded. Otherwise forward to `previous` if it
  implements the selector; without one complete `[]` (iOS shows nothing in the foreground without a delegate).
- `didReceive response`: Reception payload with `UNNotificationDefaultActionIdentifier` → tap routed through
  `NotificationRouting` (receive-and-open, or just open after an earlier receipt), subject to the launch-tap marker
  rule below; dismiss/custom actions route nothing but still complete; never forwarded. Otherwise forward to
  `previous` if it implements the selector; else complete.
- `openSettingsFor` → forward only when implemented by previous.
- The proxy is `@MainActor final class … : NSObject, UNUserNotificationCenterDelegate` using the completion-handler
  variants only (never the async variants).

### Cold start and background taps
- Scene path: `registrar.addSceneDelegate(plugin)`; `scene(_:willConnectTo:options:)` reads
  `connectionOptions?.notificationResponse`; Reception payload with the default action → tap keyed
  `identifier|date`; returns `false` (never consumes for others).
- Legacy path: `application(_:didFinishLaunchingWithOptions:)` reads `launchOptions[.remoteNotification]`; Reception
  payload → tap keyed by the alias `"launch"`; returns `true` always.
- Before the first configure such a tap is kept as the pending tap in `NotificationRouting` (latest wins); once
  configured with `handlesNotifications: true` taps route immediately. That configure schedules the drain on the main
  actor 500 ms later, so the appearance and language settings Dart sends right after `configure` returns apply
  first; a later configure reschedules it. The drain opens the chat once and records the tap's key; opting out
  cancels it and discards the pending tap.
- While the pending tap waits, a proxy tap for the same conversation is its duplicate (scene path: same key; legacy:
  no identifier to match): recorded as opened, not routed. The drain still opens the chat once.
- Launch-tap marker: when the drain routes a `"launch"` tap whose duplicate has not arrived yet, routing arms a
  marker, because iOS's later proxy delivery of the same response cannot match by key. Within 10 s of the drain,
  the first proxy tap for that conversation whose notification was delivered before this launch (the routing's
  launch date, at the latest the launch-tap capture) and that would otherwise receive-and-open is ignored, and the
  marker clears; it also clears after 10 s or on opt-out. Afterwards every tap routes.
- Running/background taps arrive through the proxy's `didReceive`.
- `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` is **receipt only** (never a tap) and only
  after a configure with `handlesNotifications: true`: Reception payload → direct
  `Reception.shared.handlePushNotification(userInfo:, openChat: false)` (not recorded in routing), complete
  `.noData`, return `true`; otherwise return `false`.

### Routing state (`NotificationRouting`)
- Port of RN: per key `receive` / `receiveAndOpen` / `open` / `ignore`; proxy receipts and taps share the machine so
  receipt-then-tap yields `open`, not a second receive-and-open.
- Deterministic bound: at most 64 keys, oldest evicted first. The pending tap and the launch marker are part of the
  same pure state machine (native tests in `tool/native_tests`). Lives in `ReceptionNotifications.shared`, so it
  survives hot restarts; nothing is replayed to Dart.

### Opt-out (`handlesNotifications: false`)
- Gates launch and scene capture, pending-tap draining, fetch handling and proxy installation. An opt-out configure
  discards the pending tap and clears the launch-tap marker.
- If a proxy is already installed from an earlier configure and a later configure opts out: the proxy becomes
  pass-through (forwards everything, handles nothing); if it still owns `center.delegate`, `previous` is restored.
  A later opt-in reinstalls it only if `previous` is still the delegate. Never overwrite a newer delegate.
- Apps then call `Reception.handlePushNotification(payload, openChat:)` from their own bridge; `Reception.isChatOpen`
  drives their presentation policy.

### Compatibility statements for the docs
- firebase_messaging ≥ 17.0.0 for apps that use Firebase (older versions complete unrelated notifications and
  mis-implement the scene callback). Configure Reception after `Firebase.initializeApp()`; before or after `runApp`
  both work, since Firebase sets its delegate at launch.
- flutter_local_notifications: keep its documented AppDelegate setup; Reception wraps whatever delegate exists at configure.
- Minimum Flutter 3.44: SwiftPM plugins need the `FlutterFramework` package that Flutter creates from 3.44 (verified
  on 3.44.0 and 3.47.8); the scene delegate API exists since 3.38.
