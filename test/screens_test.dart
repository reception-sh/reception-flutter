import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reception_flutter/reception_flutter.dart';
import 'package:reception_flutter/src/messages.g.dart';
import 'package:reception_flutter/src/reception.dart' show resetReception;

import 'fake_host.dart';

// Complements the screens test in reception_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeHost host;
  late List<String> logs;
  late List<String> opened;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    resetReception();
    host = FakeHost();
    logs = captureLogs();
    opened = [];
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  ReceptionScreen plain(String id) =>
      ReceptionScreen(id, onOpen: () => opened.add(id));

  test('isValid follows the SDK ID rule and needs a non-blank value name', () {
    for (final id in ['settings', 'A1_b.c-d', '9', 'a' * 64]) {
      expect(plain(id).isValid, isTrue, reason: id);
    }
    for (final id in ['', '-leading', '.x', 'has space', 'ü', 'a' * 65]) {
      expect(plain(id).isValid, isFalse, reason: id);
    }
    final order = ReceptionScreen.withValue(
      'order',
      value: 'Order number',
      onOpenWithValue: (_) {},
    );
    expect(order.isValid, isTrue);
    expect(order.valueName, 'Order number');
    expect(order.onOpen, isNull);
    expect(plain('settings').valueName, isNull);
    expect(plain('settings').onOpenWithValue, isNull);
  });

  test('one invalid entry ignores the whole list', () async {
    Reception.screens = [plain('settings')];
    Reception.screens = [plain('other'), plain('has space')];
    await pumpEventQueue();
    expect(Reception.screens.map((screen) => screen.id), ['settings']);
    expect(logs, ['[Reception] Invalid screens; ignored.']);
    expect(host.callsTo('setScreens'), hasLength(1));
  });

  test('the list and its payload are captured at assignment', () async {
    final list = [plain('settings')];
    Reception.screens = list;
    list.add(plain('later'));
    await pumpEventQueue();
    expect(Reception.screens.map((screen) => screen.id), ['settings']);
    expect(() => Reception.screens.add(plain('x')), throwsUnsupportedError);
    final sent = host.callsTo('setScreens').single.single! as List<Object?>;
    expect(sent.cast<ScreenMessage>().map((screen) => screen.id), ['settings']);
  });

  test('a screen sees the closed-chat state the host sends first', () async {
    final chatOpen = <bool>[];
    Reception.screens = [
      ReceptionScreen(
        'settings',
        onOpen: () => chatOpen.add(Reception.isChatOpen.value),
      ),
    ];
    await host.send('onState', [snapshot(revision: 5, isChatOpen: true)]);
    await host.send('onState', [snapshot(revision: 6)]);
    await host.send('onScreen', ['settings', null]);
    expect(chatOpen, [false]);
  });

  test(
    'a throwing screen callback is reported, not sent back to the host',
    () async {
      final errors = captureErrors();
      Reception.screens = [
        ReceptionScreen('settings', onOpen: () => throw StateError('failed')),
      ];
      // FakeHost.send throws if Dart replied with an error.
      await host.send('onScreen', ['settings', null]);
      expect(errors.single.exception, isA<StateError>());
      expect(errors.single.library, 'reception_flutter');
    },
  );

  test('a hot restart empties the list until it is set again', () async {
    Reception.screens = [plain('settings')];
    await pumpEventQueue();
    resetReception();
    expect(Reception.screens, isEmpty);
    await host.send('onScreen', ['settings', null]);
    expect(opened, isEmpty);
  });

  test('off iOS the list stays empty and the host is untouched', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    Reception.screens = [plain('settings')];
    await pumpEventQueue();
    expect(Reception.screens, isEmpty);
    expect(host.calls, isEmpty);
  });

  test('only the first 50 unique screens are kept, with one warning', () async {
    Reception.screens = [
      plain('s0'),
      plain('s0'),
      for (var i = 1; i < 52; i++) plain('s$i'),
    ];
    await pumpEventQueue();
    expect(Reception.screens, hasLength(50));
    expect(Reception.screens.last.id, 's49');
    final sent = host.callsTo('setScreens').single.single! as List<Object?>;
    expect(sent, hasLength(50));
    expect(logs, [
      '[Reception] Only the first 50 screens are kept; 2 more ignored.',
    ]);
    Reception.screens = [for (var i = 0; i < 50; i++) plain('s$i')];
    expect(logs, hasLength(1), reason: 'exactly 50 is fine');
  });

  test('screens open while an embedded chat keeps isChatOpen true', () async {
    final chatOpen = <bool>[];
    Reception.screens = [
      ReceptionScreen(
        'settings',
        onOpen: () => chatOpen.add(Reception.isChatOpen.value),
      ),
    ];
    await host.send('onState', [
      snapshot(revision: 5, isChatOpen: true, unreadCount: 2),
    ]);
    await host.send('onScreen', ['settings', null]);
    expect(chatOpen, [true]);
    expect(Reception.isChatOpen.value, isTrue);
    expect(Reception.unreadCount.value, 2);
  });
}
