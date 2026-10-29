// Extended verification scenarios driven from Dart (no XCUITest). Select with
// --dart-define=EXT_MODE=identity|automation|ipad. Prints SHOT:<name> markers for
// host-side `xcrun simctl io <device> screenshot`.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reception_flutter/reception_flutter.dart';
import 'package:reception_flutter_example/main.dart' as app;

const mode = String.fromEnvironment('EXT_MODE');

Future<void> shot(WidgetTester tester, String name) async {
  debugPrint('SHOT:$name');
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<bool> until(
  WidgetTester tester,
  bool Function() condition,
  Duration timeout,
) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) return false;
    await tester.pump(const Duration(milliseconds: 100));
  }
  return true;
}

Future<void> tap(WidgetTester tester, String label) async {
  final finder = find.textContaining(label);
  await tester.scrollUntilVisible(finder.first, 200);
  await tester.tap(finder.first);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('extended: $mode', (tester) async {
    await app.main();
    await tester.pumpAndSettle();
    expect(Reception.isConfigured, isTrue);
    switch (mode) {
      case 'identity':
        await tap(tester, 'Identify with token');
        await tap(tester, 'Open chat');
        final rejected = await until(
          tester,
          () => app.events.value.any((e) => e.startsWith('identityRejected')),
          const Duration(seconds: 20),
        );
        debugPrint('RESULT rejected=$rejected events=${app.events.value}');
        await shot(tester, 'identity-chat');
        await Reception.closeChat();
        await tester.pump(const Duration(seconds: 1));
        await tester.scrollUntilVisible(find.byKey(const Key('events')), 300);
        await shot(tester, 'identity-events');
      case 'automation':
        expect(Reception.isChatOpen.value, isFalse);
        final start = DateTime.now();
        await Reception.track('paywall_declined', opensChat: true);
        final opened = await until(
          tester,
          () => Reception.isChatOpen.value,
          const Duration(seconds: 5),
        );
        debugPrint(
          'RESULT automation opened=$opened after '
          '${DateTime.now().difference(start).inMilliseconds} ms',
        );
        await tester.pump(const Duration(seconds: 3));
        await shot(tester, 'automation-chat');
        await Reception.closeChat();
        await until(
          tester,
          () => !Reception.isChatOpen.value,
          const Duration(seconds: 5),
        );
        await tester.pump(const Duration(seconds: 2));
        await Reception.track('no_matching_automation', opensChat: true);
        final unexpected = await until(
          tester,
          () => Reception.isChatOpen.value,
          const Duration(seconds: 6),
        );
        debugPrint('RESULT unmatched opened=$unexpected');
        await shot(tester, 'automation-unmatched');
      case 'ipad':
        await shot(tester, 'ipad-home');
        await tap(tester, 'Open chat');
        await until(
          tester,
          () => Reception.isChatOpen.value,
          const Duration(seconds: 5),
        );
        await shot(tester, 'ipad-sheet');
        await shot(tester, 'ipad-sheet-dark');
        await Reception.closeChat();
        await tester.pump(const Duration(seconds: 1));
        await tap(tester, 'Embedded chat');
        await tester.pumpAndSettle();
        await shot(tester, 'ipad-embedded');
        await shot(tester, 'ipad-embedded-dark');
        debugPrint('RESULT ipad done');
      default:
        fail('unknown EXT_MODE $mode');
    }
  });
}
