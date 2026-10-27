# Verification example

A plain Material app that exercises the whole `reception_flutter` API against a local
Reception backend. Start the backend (default `http://localhost:3123`; override with
`--dart-define=RECEPTION_SERVICE_URL=http://localhost:3000`) and copy the App ID of a
local test app whose bundle identifier is `sh.reception.receptionFlutterExample`.

```sh
flutter run -d <simulator> --dart-define=RECEPTION_APP_ID=app_...
```

Never commit the App ID. With an App ID the app configures in `main()`, so the SDK's
launch arguments and push cold starts work without tapping:

```sh
flutter build ios --simulator --debug --dart-define=RECEPTION_APP_ID=app_...
xcrun simctl install <device> build/ios/iphonesimulator/Runner.app
xcrun simctl launch --terminate-running-process <device> sh.reception.receptionFlutterExample -ReceptionSetupCheck app_...
```

Add `--dart-define=RECEPTION_AUTOSTART=false` to configure with the Configure button
instead (and to try the calls before configure). Debug builds configure through
`configureReceptionForTesting` from `package:reception_flutter/testing.dart`, which only
accepts a localhost service; release builds call `Reception.configure`.

- **Hot restart:** in `flutter run`, press `R`. The console (`[example] …`) shows the
  unread count and available paywalls being re-read from native.
- **Paywalls:** `plans` and `hidden` are registered; availability allows only `plans`
  after 150 ms. The hanging switch installs a callback that never completes; native
  fails it closed after five seconds. Refresh paywalls re-evaluates with
  `invalidate: true`. The paywall callback only records the ID and chat visibility.
- **Push:** Enable notifications asks for permission through the example's own
  method channel in `ios/Runner/AppDelegate.swift` (the plugin never prompts, and
  `xcrun simctl privacy` has no notifications service), then calls
  `registerForPushIfAuthorized`. Send `../verification/reception-push.apns` with
  `xcrun simctl push <device> sh.reception.receptionFlutterExample <file>` after
  replacing the conversation ID. The example has no Push capability, so no APNs
  token is registered; simulated pushes work without one.
- **Integration test:** `flutter test integration_test -d <device>
  --dart-define=RECEPTION_APP_ID=app_... --dart-define=RECEPTION_AUTOSTART=false`.
  Add `--dart-define=EXPECT_UNREAD=true` after a dashboard reply to wait for unread.

`ios/Runner/Info.plist` lists `en` and `de` in `CFBundleLocalizations`; without it iOS
resolves the app, and the chat, to English regardless of the device language.
