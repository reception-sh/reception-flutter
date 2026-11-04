# Reception for Flutter

Native support chat, with replies managed in the Reception dashboard.
The chat runs entirely in the official Reception SDKs for iOS and Android.

Requires Flutter 3.44+ (verified on 3.44 and 3.47), Dart 3.12+, iOS 17+ with
Xcode 26, and Android 7.0+ (API 24, Flutter's default `minSdk`). Web and desktop
calls do nothing.

## 1. Install

```sh
flutter pub add reception_flutter
```

Swift Package Manager and CocoaPods both work without Podfile edits. Set the iOS
deployment target to 17.0 or higher at the project level (Xcode: Runner project →
Info → iOS Deployment Target, or the three `IPHONEOS_DEPLOYMENT_TARGET` entries in
`ios/Runner.xcodeproj/project.pbxproj`), and raise any Runner target-level entries
below 17.0. If `ios/Podfile` exists and pins an older platform, set
`platform :ios, '17.0'` there too; a `post_install` hook that forces an older
target on all pods must use 17.0 or skip `reception_flutter`. Reception follows the languages
declared under `CFBundleLocalizations` in `ios/Runner/Info.plist`.

On Android the plugin depends on `sh.reception:reception` from Maven Central;
Gradle fetches it, and the app needs no edits. Keep the `FlutterActivity`'s
`android:windowSoftInputMode="adjustResize"` from Flutter's template so the
keyboard never covers an embedded chat.

## 2. Configure

Configure once in `main()`, before showing Support, and after
`Firebase.initializeApp()` and any other notification plugin's setup:

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

Call this from your app's Support button, shown on iOS and Android; keep your
existing contact path on web and desktop:

```dart
await Reception.openChat();
```

Report app events for automations set up in the dashboard with
`await Reception.track('paywall_declined', opensChat: true)`.

Link cards sent from the dashboard open websites, other apps, the App Store,
Mail and the phone without code. To let them open screens of your app, list
the screens once in `main()`:

```dart
Reception.screens = [
  ReceptionScreen('settings', onOpen: () => router.push('/settings')),
  ReceptionScreen.withValue('order', value: 'Order number',
      onOpenWithValue: (number) => router.push('/orders/$number')),
];
```

Follow the [Flutter guide](https://reception.sh/docs/flutter) to match your app's
theme, add unread badges, identify customers, and connect paywalls or embedded chat.

On Android, `ReceptionAppearance.fontFamily` names a family from the `fonts:`
section of your `pubspec.yaml`, and `closeImage` and
`ReceptionWelcomeIcon.image` name drawable resources in
`android/app/src/main/res/drawable` (vector or bitmap drawables are drawn
sharp at any size; other drawables are rasterized at their intrinsic size;
Flutter assets are not supported); list those in a `tools:keep` resource file
so release builds do not strip them. The embedded `ReceptionChatView` works in
`FlutterActivity` and `FlutterFragmentActivity`, photos and the notification
card included, also with a cached engine whose activity is recreated.
`ReceptionChatView` claims vertical drags, so it scrolls inside a `ListView`;
pass `gestureRecognizers: {}` to leave them to the list.

## Push

**iOS:** add the Push Notifications capability to the Runner target and your Apple push
credentials in the dashboard. The plugin then registers the APNs token, shows
Reception banners while chat is closed, and opens chat on taps, including cold
starts. The plugin never prompts for permission itself; when **Ask for push
notifications** is on in the dashboard, the chat asks with a card after the
person's message and the plugin registers the token it gets. After your own
permission request, call `await Reception.registerForPushIfAuthorized()`.
Notifications from Firebase and other services keep reaching their handlers;
see the
[push setup](https://reception.sh/docs/flutter#push).

**Android:** push uses Firebase Cloud Messaging. Add your Firebase service account
in the dashboard, and Firebase to the app: `google-services.json` in
`android/app/`, the `com.google.gms.google-services` Gradle plugin, and either
the `firebase_messaging` package or, without it, the
`com.google.firebase:firebase-messaging` Gradle dependency. Nothing else: the
plugin registers the FCM token once notifications are allowed (the chat asks
with its card, or call `Reception.registerForPushIfAuthorized()` after your own
request), shows Reception's replies while the chat is closed, also when the app
was not running, and opens the chat on taps, including cold starts. Do not add
the SDK's `ReceptionMessagingService` to your manifest; the plugin already
receives Reception messages beside `firebase_messaging`. With
`firebase_messaging`, Reception messages also arrive in `onMessage` and
`onBackgroundMessage` as data-only messages with a `reception` field: skip them
there. With `configure(handlesNotifications: false)` the plugin shows nothing and a
tap on a notification it showed earlier only brings the app forward; show your
own notification and call `Reception.handlePushNotification(message.data)` on
its tap.

## Compatibility

Web and desktop have no Reception native code. Calls complete immediately, log
once, and return default state.

Do not also add the native `reception-ios` package: the plugin already bundles
the SDK, and two copies would share the same storage. On Android the plugin
brings `sh.reception:reception` itself; do not configure that SDK from native
code as well.

License: MIT.
