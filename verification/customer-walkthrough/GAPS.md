# Customer walkthrough: gaps in the setup prompt and docs

Run 2026-10-27, 20:20–21:00 CET. A coding agent got the dashboard setup prompt ("Walkthrough", local base URL
`http://localhost:3123`) for a fresh `flutter create` app with Home, Settings, a light/dark theme setting, an in-app
English/German language setting (`CFBundleLocalizations` en, de), a name-only sign-in and a fake paywall with two
products (no store library). Answers to the two questions: Support icon button on Home plus a Settings row; user
details plan and sign-up date. Evidence: numbered screenshots, `commands.txt`, `integration.diff`.

Allowed deviation: `configureReceptionForTesting(appId:, serviceUrl: http://localhost:3123)` from
`package:reception_flutter/testing.dart` instead of `Reception.configure`, and a path dependency instead of pub.dev.

The docs, the prompt and the plugin changed in the middle of the run (reception d5aa5e63..ebba025d at 20:43–20:45,
reception-flutter f07e7d3 at 20:43 and a6dfe89 at 20:52). The app was first integrated against the earlier text,
then updated to the current one and checked again. Gaps that the 20:43–20:45 commits already fixed are listed
under "Fixed during the run". All other gaps below still apply to the current text.

## Worked without guessing

Platform detection; `flutter pub add`; raising the three project-level `IPHONEOS_DEPLOYMENT_TARGET` entries (no
Podfile in a SwiftPM project); configure placement in `main()`; the docs comment; the `AGENTS.md` line;
`CFBundleLocalizations` (already present); `Reception.unreadCount` with `ValueListenableBuilder`; `openChat`;
`identify` with a name only; `setMetadata`; `logout` on sign-out; the iOS-only entry check; the entitlements file
without Xcode (current text); the build, install and launch commands; the bundle identifier; the log command; the
setup check (passed on the first launch both times); both previews; the dashboard reply as the unread badge; dark
mode and the German language override in the chat; the own-screen paywall card (sheet closes, the Flutter paywall
opens, chat reopens after Close).

## Open gaps

### G1 (high): "test push" cannot work in an app without a permission flow, and nothing says so up front

Text today:
- Prompt step 9: "Once push is set up, they can say "test push": then make sure the app has notification permission
  through its own flow (ask the developer to allow it in the simulator if needed) … If the app never asks for
  notification permission, say that replies then only show inside the app."
- `flutter.md#push`: "Keep your existing permission flow; Reception never requests permission."

What happened: a fresh Flutter app has no permission flow and Flutter has no built-in permission API, so there is
nothing for the developer to allow: iOS lists no notification switch for an app that never requested
authorization. `xcrun simctl push` with the documented payload is accepted ("Notification sent"), SpringBoard
saves the request and sets the icon badge, but shows no banner ("Got effective section info [ hasResult: 0 ]"),
in the background and within 5 s (screenshots 07 and 17). So "push banner" and "chat opened by tap" could not be
shown. The assumption that `simctl push` needs no permission is true for delivery, not for display. The docs give
no Flutter code for a permission request, so none was added, as instructed.

Fix, `reception/src/lib/setup-prompt.ts`, step 9, replace the "test push" bullet with:

> - Once push is set up, they can say "test push". The simulator shows a banner only if the app has notification
>   permission. If the app already asks for it, have the developer allow it there; if it never asks, say that
>   replies then only show inside the app and that a banner test needs a permission request first, and offer to add
>   one at a point where the app would ask anyway (with consent, never at launch only for Reception). Then send the
>   app to the background by launching Settings (xcrun simctl launch <device> com.apple.Preferences), have them
>   reply from the dashboard and screenshot the notification. Report push as working only when one arrived.

Fix, `reception/content/docs/flutter.md#push`, after "After your existing permission request completes, call the
nonprompting refresh …" add:

> If the app has no permission request yet, add one only at an intentional point (for example a notification
> setting or after onboarding), with the package the app already uses for notifications:
> `FirebaseMessaging.instance.requestPermission()` (firebase_messaging) or
> `IOSFlutterLocalNotificationsPlugin.requestPermissions(alert: true, badge: true, sound: true)`
> (flutter_local_notifications), then `await Reception.registerForPushIfAuthorized()`. Without permission, iOS
> shows no Reception banner, also not for `xcrun simctl push` on the simulator.

Optional plugin feature instead: a Debug-simulator-only launch argument (like `-ReceptionSetupCheck`), for example
`-ReceptionRequestPushPermission`, that asks once so the test push works without app code.

### G2 (medium): the own-screen Flutter paywall file assumes a store library; an app without one has to rewrite it

Text today:
- Prompt step 5: "The app's own paywall screen, with RevenueCat or StoreKit: ReceptionStorePaywall (… 
  reception_store_paywall.dart) … In React Native and Flutter the file reads RevenueCat customer info; if the app
  uses another store library (such as Adapty or in_app_purchase), replace those RevenueCat calls …" and "copy the
  matching file … unchanged apart from its placeholders".
- `paywalls.md#flutter-custom`: "If the app uses another store library, use its current entitlements, subscription
  dates and purchase-change listener in these same places; do not add RevenueCat just for Reception."

What happened: the app's paywall has no store library yet (common for a paywall screen built before purchases,
and for apps that sell through a web checkout). The file imports `purchases_flutter`. I had to invent the
replacement: remove the import, `subscriptionMetadata(CustomerInfo)`, the customer-info listener and the now unused
`syncsSubscriptionMetadata` flag, and add an `_ownedProductIds()` hook that returns an empty set (see
`integration.diff`, `lib/reception_store_paywall.dart`). The card then worked, but nothing in the prompt or docs
says what to do with no store library, nor that the "plan" detail then comes from the app's own field.

Fix, `reception/src/lib/paywall-prompt.ts`, own-screen bullet, append:

> Without any store library, keep the file's structure, remove the RevenueCat import, listener and
> subscriptionMetadata, make ownership an empty set (every product stays available) and send the chosen user
> details from the app's own fields.

Better: add a store-agnostic variant to `paywalls.md#flutter-custom` with one marked hook
(`Future<Set<String>> ownedProductIds()` and an optional `Map<String, String> subscriptionMetadata()`), and keep the
RevenueCat version as the example that fills it.

### G3 (medium): no mapping from a Material theme to chatBackground, incomingBackground and incomingForeground

Text today, prompt step 3: "Set the selected SDK's appearance accentColor, onAccentColor, chatBackground,
incomingBackground and incomingForeground from the app's own colors … Never hardcode or invent colors."
`flutter.md#appearance` shows only `accentColor = primary` and `onAccentColor = onPrimary`.

What happened: I guessed `surface`, `surfaceContainerHighest` and `onSurface`, and mapped `ThemeMode` to
`preferredColorScheme` myself. The result looks right (screenshots 04, 08), but another agent may pick `background`,
`secondaryContainer` or leave them unset.

Fix, `reception/content/docs/flutter.md#appearance`, after the code block add:

> For a Material `ColorScheme`, use `primary` for accentColor, `onPrimary` for onAccentColor, `surface` for
> chatBackground, `surfaceContainerHighest` for incomingBackground and `onSurface` for incomingForeground, each as
> `ReceptionColor.adaptiveOf(light: lightTheme.colorScheme.x, dark: darkTheme.colorScheme.x)`. If the app has its own
> light/dark setting, map `ThemeMode.light` to `ReceptionColorScheme.light`, `ThemeMode.dark` to
> `ReceptionColorScheme.dark` and `ThemeMode.system` to `null`, and assign a new `ReceptionAppearance` when it
> changes.

### G4 (low): the Flutter guide does not say what languageOverride takes

Text today, `flutter.md#appearance`: "`Reception.languageOverride = selectedLanguage;`". The type (a BCP 47
`String?`) is only in the Swift page `language.md` and the Dart source.

Fix, `reception/content/docs/flutter.md#appearance`, replace the comment line with:

> // Only if your app has its own language picker: a BCP 47 tag such as 'de' or 'pt-BR'
> // (Locale.toLanguageTag()), or null to follow the app's iOS localization.
> Reception.languageOverride = selectedLocale?.toLanguageTag();

### G5 (low): a local sign-in that stores only a name falls between "Name without sign-in" and "Accounts"

Text today, prompt step 5: "Name without sign-in: … call identify with no user ID and that name …" and "Accounts,
only if users sign in to the app, with or without a server … Wherever the app ends a signed-in session
(sign-out …): call logout".

What happened: the app has "Sign in" / "Sign out" but no user ID. I treated it as an account (identify with the name,
`logout` on sign-out, which starts a new, empty chat, screenshot 12). The prompt does not decide this.

Fix, `reception/src/lib/setup-prompt.ts`, step 5, after the "Accounts" line add:

> A sign-in that stores only a name on the device counts as an account: identify with that name and no user ID, and
> call logout on its sign-out.

(Or the opposite rule, if Reception prefers keeping the chat; either way it should be stated.)

### G6 (low): "every menu row on the way" is unclear for a toolbar button on the same screen as the entry

Text today, prompt step 4: "Show the live unread count on each entry and on every menu row on the way".

What happened: Home has the Support icon button and a Settings gear that leads to the Settings Support row. A badge
on the gear would show the same reply twice on one screen; I left it off.

Fix, `reception/src/lib/setup-prompt.ts`, step 4, after that sentence add:

> Skip the way to a second entry when the screen already shows the first entry's badge.

### G7 (low): no Flutter snippet for the iOS badge look on an icon button

Text today: prompt step 4 asks for "a system red capsule with the white count centered … at the top right of round
icon buttons"; `flutter.md#unread` shows a settings row and suggests Material's `Badge` for tabs, whose default
color is `colorScheme.error`, not system red.

What happened: I built a capsule with `CupertinoColors.systemRed` and a `Stack`. My first version stretched to the
row height inside a `ListTile` trailing `Row` (screenshot history in `commands.txt`), fixed in the design round.

Fix, `reception/content/docs/flutter.md#unread`, after the SupportRow example add:

> Without an existing badge style, Material's `Badge` gives the iOS look on icon buttons and rows:
> `Badge(isLabelVisible: unread > 0, backgroundColor: CupertinoColors.systemRed.resolveFrom(context),
> textColor: Colors.white, label: Text('$unread'), child: const Icon(Icons.support_agent_outlined))`.

### G8 (low): paywall helper account-switch rule for apps without vendor accounts

Text today, `paywalls.md#flutter`: "Before changing accounts, call `stop()`, await Reception's logout …, then the
vendor's login/logout, then start the helper again for that account."

What happened: with no vendor account the helper holds no account state; I did not stop and restart it around
`logout`. Fix, same paragraph, append: "Without a vendor account (no store library), keep the helper running."

### G9 (cosmetic): previews show English example messages in a German app

With `languageOverride = 'de'` the conversation preview shows German UI ("Gesendet", "Nachricht", "Di.") but
English example messages (screenshot 16). A German developer sees a mixed screenshot in the design round. Fix:
localize the preview's example messages, or say in prompt step 7c: "The example messages are English in every
language."

## Fixed during the run (current text, verified in the second build)

- Push capability without Xcode: the start text said only "In Xcode, … add Push Notifications". The current
  `flutter.md#push` and prompt give `ios/Runner/Runner.entitlements` and `CODE_SIGN_ENTITLEMENTS` for Debug, Release
  and Profile. Verified: the ad-hoc simulator build succeeds and its `__entitlements` section contains
  `aps-environment`.
- Flutter push code: the current prompt says the plugin does all of it natively; only
  `registerForPushIfAuthorized()` after the app's own permission request.
- Support entry on iOS only (`supportsReception`); log predicate `subsystem BEGINSWITH "com.reception"`; booting a
  simulator if none is booted.
- Type names: `Appearance`, `AppearanceColor`, `Identity`, `PreferredColorScheme` became `ReceptionAppearance`,
  `ReceptionColor`, `ReceptionIdentity`, `ReceptionColorScheme` in docs and plugin. Code written against the earlier
  text no longer compiles; fine before the first pub.dev release, but after it a rename needs a deprecation path.

## Local environment only (not customer gaps)

- On the :3123 dev server, `llms.txt`, the doc pages and the rendered prompt in `get-started.md` link to
  `http://localhost:3000`, and the code login redirects to :3000 (`AUTH_URL`). The session cookie still works on
  :3123.
- Synara browser and device tools refused writes (`caller_turn_inactive`); the dashboard was driven with headless
  Chrome over CDP and the simulator with the throwaway XCUITest driver in `/tmp/rfv/driver`.
