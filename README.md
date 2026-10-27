# Reception for Flutter

Native support chat, with replies managed in the Reception dashboard.
The chat runs entirely in the official Reception iOS SDK.

Requires Flutter 3.38+ (verified on 3.47), Dart 3.10+, iOS 17+, and Xcode 26.
The plugin runs on iOS only; Android and web calls do nothing.

## 1. Install

```sh
flutter pub add reception_flutter
```

Swift Package Manager and CocoaPods both work without Podfile edits. Set the iOS
deployment target to 17.0 or higher at the project level (Xcode: Runner project →
Info → iOS Deployment Target, or the three `IPHONEOS_DEPLOYMENT_TARGET` entries in
`ios/Runner.xcodeproj/project.pbxproj`). If `ios/Podfile` exists and pins an older
platform, set `platform :ios, '17.0'` there too. Reception follows the languages
declared under `CFBundleLocalizations` in `ios/Runner/Info.plist`.

## 2. Configure

Configure once in `main()`, before showing Support:

```dart
import 'package:flutter/widgets.dart';
import 'package:reception_flutter/reception_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Reception.configure(appId: 'app_YOUR_APP_ID');
  runApp(const MyApp());
}
```

## 3. Open chat

Call this from your app's Support button:

```dart
await Reception.openChat();
```

Report app events for automations set up in the dashboard with
`await Reception.track('paywall_declined', opensChat: true)`.

Follow the [Flutter guide](https://reception.sh/docs/flutter) to match your app's
theme, add unread badges, identify customers, and connect paywalls or embedded chat.

## Push

Add the Push Notifications capability to the Runner target and your Apple push
credentials in the dashboard. The plugin then registers the APNs token, shows
Reception banners while chat is closed, and opens chat on taps, including cold
starts. It never requests permission: after your own permission request, call
`await Reception.registerForPushIfAuthorized()`. Notifications from Firebase and
other services keep reaching their handlers; see the
[push setup](https://reception.sh/docs/flutter#push).

## Compatibility

Android and web have no Reception native code. Calls complete immediately, log
once, and return default state.

Do not also add the native `reception-ios` package: the plugin already bundles
the SDK, and two copies would share the same storage.

License: MIT.
