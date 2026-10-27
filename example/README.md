# Verification example

A plain Material app that exercises the whole `reception_flutter` API. Copy the App ID
of a Reception app whose bundle identifier is `sh.reception.receptionFlutterExample`:

```sh
flutter run -d <simulator> --dart-define=RECEPTION_APP_ID=app_...
```

This configures with `Reception.configure` against the production service. To use a
local Reception backend instead, add its URL:

```sh
flutter run -d <simulator> --dart-define=RECEPTION_APP_ID=app_... \
  --dart-define=RECEPTION_SERVICE_URL=http://localhost:3123
```

The app then configures through `configureReceptionForTesting` from
`package:reception_flutter/testing.dart`, which works only in Debug simulator builds with
a localhost URL and does nothing otherwise. The status line shows `Configured` or
`Configured: false` from the native result.

Never commit the App ID. With an App ID the app configures in `main()`, so the SDK's
launch arguments and push cold starts work without tapping:

```sh
flutter build ios --simulator --debug --dart-define=RECEPTION_APP_ID=app_...
xcrun simctl install <device> build/ios/iphonesimulator/Runner.app
xcrun simctl launch --terminate-running-process <device> sh.reception.receptionFlutterExample -ReceptionSetupCheck app_...
```

Add `--dart-define=RECEPTION_AUTOSTART=false` to configure with the Configure button
instead (and to try the calls before configure).

- **Hot restart:** in `flutter run`, press `R`. The console (`[example] …`) shows the
  unread count and available paywalls being re-read from native.
- **Paywalls:** `plans` and `hidden` are registered; availability allows only `plans`
  after 150 ms. The hanging switch installs a callback that never completes; native
  fails it closed after five seconds. Refresh paywalls re-evaluates with
  `invalidate: true`. The paywall callback only records the ID and chat visibility.
- **Push:** Enable notifications asks for permission through the example's own
  method channel in `ios/Runner/AppDelegate.swift` (the plugin never prompts, and
  `xcrun simctl privacy` has no notifications service), then calls
  `registerForPushIfAuthorized`. Replace `YOUR_CONVERSATION_ID` in
  `reception-push.apns` with a conversation ID from the dashboard, then send it with
  `xcrun simctl push <device> sh.reception.receptionFlutterExample reception-push.apns`. `ios/Runner/Runner.entitlements` enables push
  (`aps-environment` development); on Apple silicon the simulator then issues an
  APNs token, visible as "Push token staged" at `ReceptionLogLevel.debug` once debug logs are
  persisted: `xcrun simctl spawn <device> log config --subsystem com.reception.sdk
  --mode "level:debug,persist:debug"`.
- **Integration test:** `flutter test integration_test -d <device>
  --dart-define=RECEPTION_APP_ID=app_... --dart-define=RECEPTION_AUTOSTART=false`.
  Add the same `RECEPTION_SERVICE_URL` define when the App ID belongs to a local backend.
  Add `--dart-define=EXPECT_UNREAD=true` after a dashboard reply to wait for unread.

`ios/Runner/Info.plist` lists `en` and `de` in `CFBundleLocalizations`; without it iOS
resolves the app, and the chat, to English regardless of the device language.
