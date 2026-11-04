# Android verification (plugin 1.2.0, unreleased)

Run 2026-11-04 on `main`. Emulator `emulator-5554` (`reception_pixel8`, Android 16, Google Play image, no Google
account), Gboard selected for the keyboard steps (the device CLI's own test IME draws nothing and reports no insets;
it re-selects itself on `fill`, so keyboard steps used `adb shell input`). Flutter 3.47.8 (`~/flutter-local`), JDK 17.
Reception Android SDK 1.0.0 from `publishToMavenLocal` of `reception-android` HEAD 43d74f5 (a copy, see CLAUDE.md).
Local backend `http://localhost:3123` on branch `android-push`, reached as `10.0.2.2:3123`. Test app "Flutter
Example" `app_lQCXNRFINXc8FEnriGpad3`, now also with the FCM service account of "Android Example" and
`androidPackageName = sh.reception.receptionFlutterExample`; Firebase project `reception-android-test`, Android app
`1:16200985775:android:840101e03117577495f85a`.

```sh
cd example
flutter run -d emulator-5554 --dart-define=RECEPTION_APP_ID=app_lQCXNRFINXc8FEnriGpad3 \
  --dart-define=RECEPTION_SERVICE_URL=http://10.0.2.2:3123
```

Team replies and cards came from scratchpad scripts run in `../reception` that call `createAgentMessage` as the
first organization member (and `sendPush` for replies) for the newest Android conversation of the test app, like the
SDK's verification (`node --env-file=.env --conditions=react-server --import ./tests/server-runtime.mjs --import tsx
<script>.mts`). Hot restart: `kill -USR2 <flutter run pid>`.

## Chat, embedded view, settings

| Step | Observed | Shot |
| --- | --- | --- |
| Launch (configure in `main()` via `configureReceptionForTesting`) | `Configured, SDK 1.0.0`, device registered; Dart `Configured: true`, `SDK 1.0.0`; `Available: plans` (the availability callback allows `plans`, filters `hidden`) | — |
| Open chat | the SDK's sheet over `FlutterActivity` with the Dart appearance (close button, chat background) | 01 |
| Type, Send | "Sent" in the Dart accent `#8A2BE2`; Dart events `chatOpened`, `messageSent` | 02, 03 |
| Team reply | arrived in the open chat (stream refresh) in the Dart incoming colors | 04 |
| Photo: picker, Done, Send | photo bubble; Dart `messageSent`, `imageSent` | 05 |
| Keyboard in the sheet (Gboard) | composer above the keyboard | 06 |
| Embedded chat (`ReceptionChatView`, hybrid composition) | history below the Flutter app bar, composer above the gesture bar | 07 |
| Tap the embedded composer | keyboard shown; first run: the chat padded the keyboard height twice (Flutter's `Scaffold` already resized); fixed with `OverlapInsets` (overlap-only insets), after which the composer sits right above the keyboard | 08 |
| Type and send in the embedded chat | sent; Dart `messageSent` | 09 |
| Photo from the embedded chat (plain `FlutterActivity`, no `ActivityResultRegistry`) | picker through the plugin's `ActivityResults`; Dart `messageSent`, `imageSent` | 10 |
| `languageOverride = 'de'` from Dart, open | "Nachricht", "Schließen" | 22 |
| System dark mode, then light, chat open | first run: light colors kept in dark (pairs resolved at assignment) — 23; after the fix the dark pair applies — 24 — and switching to light under the open chat re-applies the light pair — 25 | 23–25 |
| `--dart-define=RECEPTION_FONT_FAMILY=MaterialIcons` (a family in every app's `FontManifest.json`) | the chat draws in that font (only glyphs the icon font has), so the pubspec family reached Compose | 28 |
| Paywall card "View offer" | Dart `paywallOpened`, `onPaywall:plans, chat:true` (chat stays open, as on iOS) | 26 |
| Link card `reception-screen:order?value=4711` | Dart `linkOpened`, then `screen:order 4711, chat:false`: the sheet closed first, then Dart pushed the page | 26, 27 |
| Hanging availability on, then off | `Available:` empty while the Dart callback never answers (fail-closed), `plans` again after | — |
| Hot restart with the chat open | chat stays open natively; Dart reconnects `configured true`; after closing, `Chat open: false`, `Available: plans`; reopening sends `chatOpened` again | 21 |

## Push, Firebase on the Gradle side only (no firebase_messaging)

The example applies `com.google.gms.google-services` and `firebase-messaging` when `google-services.json` exists; no
manifest service, no Dart push code.

| Step | Observed | Shot |
| --- | --- | --- |
| Enable notifications (example channel → `POST_NOTIFICATIONS`), accept | Dart `registerForPushIfAuthorized` → SDK `Push token staged, 142 chars, production`; the backend device has the token | 11 |
| Reply, app in foreground, chat closed | `Push payload recognized`, `Notification shown` (channel `reception_replies`, color `0xff8a2be2`, tag `reception`); Dart `Unread: 1`, badge on Open chat | 12 |
| Tap it in the shade | `Chat opens once an activity is resumed` → `Chat presented` | 13, 14 |
| Reply while the chat is open | `Notification not shown, chat open`; no notification record | — |
| Home, reply, tap | shown; tap brought the app forward and opened the chat | 15, 16 |
| Home, `am kill` (task kept), reply | `Start proc … for broadcast {…/sh.reception.flutter.ReceptionPushReceiver}`; notification posted without Dart running | 17 |
| `am kill` again, tap (cold start) | process started for the trampoline, Dart configured, the pending tap drained, chat opened with the Dart appearance | 18 |
| Recents after that | **two tasks** of the example: the old one and a new one (see "Open issue") | 19 |
| Swipe the app away from Recents, reply, `am kill`, tap | one task; chat opened | 20 |

## Push with firebase_messaging 17.0.1 (temporary example change, reverted)

`firebase_core: 5.1.0`, `firebase_messaging: 17.0.1` in the example's pubspec; `main()` calls
`Firebase.initializeApp()`, registers `onBackgroundMessage` and `onMessage` loggers and reads the FCM token.

| Step | Observed | Shot |
| --- | --- | --- |
| Reply, foreground, chat closed | the plugin's notification (one record); Dart `onMessage` also got `{reception: …, title, body, badge, sound}` as documented | 29 |
| Home, reply, tap | notification shown; FlutterFire's background handler logged the data; the tap opened the chat | 30 |
| Swipe away (process gone, not force-stopped), reply | `Start proc … for broadcast {…FlutterFirebaseMessagingReceiver}`; FlutterFire's background isolate ran, and the plugin's receiver posted the notification in the same process | 31 |
| `am kill`, tap (cold start) | chat opened after configure; one task in Recents | 32 |

Not an app bug, recorded so nobody repeats it: stopping `flutter run` force-stops the app (`stopped=true`), and
Android delivers no FCM message to a force-stopped app until it is opened again.

## Open issue (SDK)

After a system kill that leaves the app's task in Recents, a cold-start tap creates a second task. Flutter's template
gives `MainActivity` `android:taskAffinity=""`; the SDK's `ReceptionNotificationActivity` (default affinity, root of
a new task) starts `getLaunchIntentForPackage` with `FLAG_ACTIVITY_NEW_TASK`, whose categories differ from the
launcher's root intent, so Android matches the dead task neither by affinity nor by intent. The chat opens correctly;
Recents shows the stale task beside the new one. Native apps (default affinity) and apps swiped away from Recents
are not affected. Fix belongs in the SDK trampoline (for example bring an existing `ActivityManager.appTasks` entry
to the front, or start the exact launcher intent). Not worked around in the plugin.

## Not verified live

- `configure(handlesNotifications: false)` on Android (receiver skips Reception messages; covered by code review only).
- Drawable names for `closeImage`/`welcomeIcon.image` (the example has none).
- `FlutterFragmentActivity` hosts (the bridge is skipped there because the activity has its own registry).
- Photo picker on Android below 13 and the notification card in the embedded view.

## Checks

```
$ flutter analyze                                   No issues found!
$ (cd example && flutter analyze)                   No issues found!
$ dart format --set-exit-if-changed .               0 changed
$ flutter test                                      +76: All tests passed!
$ (cd example/android && ./gradlew :reception_flutter:testDebugUnitTest :reception_flutter:lintDebug)
                                                    10 tests (PaywallRequests 4, ReceptionColor 3, ReceptionAssets 2,
                                                    PushToken 1), 0 failures; lint 0 issues (warnings as errors)
$ (cd example && flutter build apk --release)       ✓ Built build/app/outputs/flutter-apk/app-release.apk (48.0MB), R8
$ flutter pub publish --dry-run                     Package has 0 warnings.
```

The Kotlin sources compile without warnings; the only compiler warnings in the build come from Flutter's own Gradle
plugin sources and its deprecation notice for `org.jetbrains.kotlin.android`, which the Flutter template applies.

## Fix round 1 (audit FL-0 … FL-5)

Run 2026-11-04 on `main` (commits c7f8d21 … 29b900b). Emulator `emulator-5556` (`reception_pixel8_rn`, Android 16,
Google Play image), Flutter 3.47.8, JDK 17. Reception Android SDK 1.0.0 from `publishToMavenLocal` of a copy of
`reception-android` HEAD 28e239b (adds `ReceptionColor` pairs, `WelcomeIcon.resource`, `closeImageResource`,
`setNotificationRoutingEnabled`). Same backend and test app as above; replies from the same `agent-reply.mts` script.
Screenshots `android/fix1-*.png`.

Cached-engine hosts (debug source set only): `CachedEngineActivity` (`FlutterActivity` with `provideFlutterEngine`)
and `CachedEngineFragmentActivity` (`FlutterFragmentActivity` with `getCachedEngineId`; a provided engine would be
destroyed with its fragment, because `FlutterFragment.withNewEngine` always sets `destroy_engine_with_fragment`), both
without `configChanges`, so rotation recreates them while the engine and its platform views survive:

```sh
adb -s emulator-5556 shell settings put system accelerometer_rotation 0
adb -s emulator-5556 shell settings put system user_rotation 1   # 0 = portrait
# launched with the device CLI: open sh.reception.receptionFlutterExample --activity .CachedEngineActivity
```

| Item | Step | Observed | Shot |
| --- | --- | --- | --- |
| FL-1 | `CachedEngineActivity`, Embedded chat, rotate (Impeller, the default) | the chat survives and draws, but Flutter's own surface stays black with `EGL_BAD_ACCESS … Could not make the context current to acquire the frame` on most recreations | fix1-01 |
| FL-1 | control: the factory temporarily returns a plain orange `View` (not committed), same rotation | same black Flutter surface and EGL errors, so this is Flutter's hybrid composition with a cached engine on this emulator's Impeller GLES, not the plugin; without a platform view on screen the recreation renders | fix1-02 |
| FL-1 | same with `io.flutter.embedding.android.EnableImpeller=false` (temporary debug manifest change) | portrait ↔ landscape five times: app bar and chat lay out for each new window, no EGL errors | fix1-03 |
| FL-1 | type "Draft before rotation" in the embedded chat, rotate, Send | the draft survived the recreation (same composition, moved to the new activity's window); sent; Dart `messageSent` | fix1-04 |
| FL-2 | `CachedEngineActivity` (plain `FlutterActivity`): Add photos, rotate with the picker sheet up (window `eb09cd1` → `6ac8ae5`, `finishDrawing of relaunch`), pick, Done | the photo is in the composer of the recreated activity's chat; Send → Dart `messageSent`, `imageSent` | fix1-05 |
| FL-2 | `CachedEngineFragmentActivity` (`FlutterFragmentActivity`, launches forwarded through its own registry): draft, rotate (`7d21127` → `bbc7b8c`), Add photos, rotate under the picker (→ `832c287`), pick, Done | draft kept, photo in the composer; Send → `messageSent`, `imageSent` | fix1-06 |
| FL-5 | `MainActivity` (Impeller), "Embedded chat in a list" (`ListView`: 240 dp block, 480 dp chat, 600 dp block); drag down on the chat | the chat scrolled to older messages; the list stayed put | fix1-07 |
| FL-5 | drag up on the amber block | the list scrolled | fix1-08 |
| FL-3 | handling on, Enable notifications (allow), Home, reply "Reply one" | notification shown (`reception_replies`, tag `reception:<id>`) | — |
| FL-3 | app forward, "Configure, app owns notifications" (`configureReceptionForTesting(handlesNotifications: false)`), Home, tap "Reply one" in the shade | `Notification tap not routed, the app handles notifications`; `MainActivity` came forward, chat closed | fix1-09 |
| FL-3 | Home, reply "Reply two" | receiver skipped it: no notification record | — |
| FL-3 | "Configure" (handling on again), install the `RECEPTION_HANDLES_NOTIFICATIONS=false` build, reply "Reply three" | `Start proc … for broadcast {…ReceptionPushReceiver}`: posted before Dart ran (the stored flag was still true) | — |
| FL-3 | `am kill`, tap "Reply three" (cold start) | `Start proc … for next-top-activity {…ReceptionNotificationActivity}`, existing task restored, Dart configured with false, no chat after the 500 ms drain: `Chat open: false`, unread 3 | fix1-10 |
| FL-4 | published `{"colorScheme":"dark"}` for the test app (Prisma, revision 4), system light, `RECEPTION_REMOTE_APPEARANCE=true`, Open chat | the Dart pairs' dark variants: background `#191024`, incoming `#332641`, accent `#C89FFF` with on-accent `#22112F` | fix1-11 |
| FL-4 | restored the published appearance (`null`, revision 5); open chat, `cmd uimode night yes`, then `no` | the open chat switched to the dark pair and back (the SDK resolves pairs; the plugin no longer observes night mode) | fix1-12 |

Not verified live in this round: drawable names for `closeImage`/`welcomeIcon.image` (the example has none; the
resource/rasterize split is unit-tested on its file-name rule), restoring a chat's launcher keys and the registry after
the process died with the picker open (the picker sheet keeps the app visible, so `am kill` does not apply), iOS
behaviour of the new `gestureRecognizers` default (iOS simulator build compiles; widget test covers both platforms).

Checks:

```
$ flutter analyze                                   No issues found!
$ (cd example && flutter analyze)                   No issues found!
$ dart format --set-exit-if-changed .               0 changed
$ flutter test                                      +78: All tests passed!
$ (cd example/android && ./gradlew :reception_flutter:testDebugUnitTest :reception_flutter:lintDebug)
                                                    11 tests (PaywallRequests 4, ReceptionAssets 3, ReceptionColor 3,
                                                    PushToken 1), 0 failures; lint: No issues found.
$ (cd example && flutter build apk --release)       ✓ Built build/app/outputs/flutter-apk/app-release.apk (48.0MB)
$ (cd example && flutter build ios --simulator --debug)   ✓ Built build/ios/iphonesimulator/Runner.app
$ flutter pub publish --dry-run                     Package has 0 warnings.
```

The plugin's Kotlin compiles without warnings (`compileDebugKotlin --rerun-tasks`; the only `w:` lines are Flutter's
own Gradle sources).
