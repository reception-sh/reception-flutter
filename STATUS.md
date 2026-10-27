# Status

## Dart layer

Implemented in `lib/` per SPEC.md "Dart public API": the static `Reception` facade (`src/reception.dart`), typed
options and events (`src/types.dart`), `Appearance` with `copyWith`, native JSON shape and validation
(`src/appearance.dart`), snapshot mirror with per-key revisioned settings (`src/state.dart`), `ReceptionChatView`
(`src/chat_view.dart`), iOS guard and log helpers (`src/platform.dart`) and `ReceptionError` (`src/errors.dart`).
The host is connected lazily on the first real call (`connect()` + `ReceptionFlutterApi.setUp`); unsupported
platforms never reach it.

Tests: 42 in `test/` (Reception, settings, appearance, platforms), ported from the RN suites. Host→Dart calls
go through the real binary messenger.

Deviations and notes:
- Pigeon 29 no longer generates `TestReceptionHostApi`; `test/messages_test.g.dart` holds only an unused codec.
  `test/fake_host.dart` mocks the host channels with `TestDefaultBinaryMessengerBinding` and
  `ReceptionHostApi.pigeonChannelCodec` instead.
- `flutter analyze` reports two issues outside `lib/`/`test/` sources: the deprecated `dartTestOut` in
  `pigeons/reception.dart` and the unused `_PigeonCodec` in the generated test file. Dropping `dartTestOut` (and the
  generated file) fixes both. `dart format --set-exit-if-changed .` also flags the unformatted generated files
  (and, at the time of writing, `pigeons/`, `tool/`, `example/`). These need a decision outside the Dart layer.
- Validation the Dart type system already guarantees (appId, identity, metadata, event and paywall shapes) is not
  repeated at runtime. Remaining runtime checks: APNs token, push payload envelope, and appearance colors
  (hex or light/dark pair), `welcomeIconSize` 16–160, `welcomeIconCornerRadius` 0–80, and a finite `welcomeIconOffset`.
- `FontDesign.standard` maps to `"default"` (`default` is a reserved word in Dart). `welcomeIconOffset` is an `Offset`.
- Every `PlatformException` becomes `ReceptionError('bridge_error', 0)`: generic Swift errors carry private
  diagnostics in their Pigeon code. Typed SDK errors arrive only through `deleteData` and `IdentityRejectedEvent`, as in RN.
- Events are a sealed `ReceptionEvent` with one final subclass per case (`ChatOpenedEvent`, …, `IdentityRejectedEvent`).
- `resetReception()` (`@visibleForTesting`, not exported) simulates a hot restart in tests.
