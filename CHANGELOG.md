## 1.1.0

- Adds `Reception.opensWebLinksInApp` (default `true`): set it to `false` to hand websites from link cards and message text to Safari or the app that claims them instead of opening them in an in-app sheet over the chat.
- Limits `Reception.screens` to the 50 screens the SDK reports; extra screens are logged.
- Fixes a stale screen callback after a hot restart during the chat-closing animation.

## 1.0.0 — 2026-10-31

- Initial release: native Reception support chat for Flutter on iOS, bundling Reception iOS SDK 1.7.0. Device registration reports the original transaction IDs of App Store purchases, so App Store notifications connected in the dashboard reach the person. While typing, the chat sheet closes by dragging its grabber or title bar; a drag over the messages puts the keyboard away.
- Link cards: a message from your team can carry a button that opens a website, another app's link, an App Store page or offer code, an email address, a phone number, your app's page in iOS Settings, or one of your `screens`. Only screens need code.
- `Reception.screens` lists the places in your app that link cards can open, each `ReceptionScreen('settings', onOpen: …)`, or `ReceptionScreen.withValue('order', value: 'Order number', onOpenWithValue: (number) => …)` for a screen that takes a value from the link. The dashboard offers them by name and sends a screen link only to app versions that list it; the callback runs after the chat closes. Assign it in `main()`; a hot restart clears it.
- The chat can ask for notification permission right after the person's message, when **Ask for push notifications** is on in the dashboard, and confirms under their latest message that replies will arrive as notifications. Hide that line with `ReceptionAppearance.hidesPushStatus`. No code is needed beyond the push setup.
