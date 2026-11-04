# iOS: `ReceptionChatView` gesture default

Run 2026-11-04 on `main` at a2f214d. iPhone 17 Pro, iOS 26.5 (simulator 1B82EA4D-9E6C-401B-9BF1-DF6EEE286309),
Flutter 3.47.8, debug simulator build of the example against the local backend (`RECEPTION_SERVICE_URL=
http://localhost:3123`, test app "Flutter Example"). Driven with the device CLI; drags are `swipe` flings in points.
History: 20 messages "Gesture check 1…20" sent from the embedded composer first.

| Step | Observed | Shot |
| --- | --- | --- |
| "Embedded chat in a list" (`ListView`: amber block, 480 dp chat, teal block), opened at the latest message | chat shows checks 3–12 | ios-gestures-01 |
| drag down on the chat (150,450 → 150,720) | the chat scrolled to its first message ("Gesture check 1" under the date); the amber block and list stayed put | ios-gestures-02 |
| drag up on the amber block (200,330 → 200,140) | the list scrolled (teal block fills the screen); the chat kept its own position | ios-gestures-03 |
| "Embedded chat" (full screen), opened at the latest message | checks 6–20 | ios-gestures-04 |
| drag down on the chat (200,250 → 200,700) | the chat scrolled to its first message | ios-gestures-05 |

Result: the default `gestureRecognizers` (vertical drags claimed by the platform view) behave on iOS as on Android
(fix round 1, FL-5 in android.md): drags on the chat scroll the chat, drags elsewhere scroll the list, and the
full-screen embedded chat still scrolls.
