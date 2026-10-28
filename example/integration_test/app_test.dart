// Drives the example app on an iOS simulator against the local backend:
//   flutter test integration_test -d <device> \
//     --dart-define=RECEPTION_APP_ID=app_... \
//     --dart-define=RECEPTION_SERVICE_URL=http://localhost:3123 \
//     --dart-define=RECEPTION_AUTOSTART=false
// Add --dart-define=EXPECT_UNREAD=true after a dashboard reply to wait for the
// unread count.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reception_flutter/reception_flutter.dart';
// Simulates a hot restart on the Dart side (native state is kept).
// ignore: implementation_imports
import 'package:reception_flutter/src/reception.dart' show resetReception;
import 'package:reception_flutter_example/main.dart' as app;

const expectUnread = bool.fromEnvironment('EXPECT_UNREAD');

Future<void> until(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  required String reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Timed out: $reason');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

List<String> available() =>
    Reception.availablePaywalls.value.map((paywall) => paywall.id).toList();

Future<void> tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.scrollUntilVisible(finder, 200);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exercises the public API on iOS', (tester) async {
    await app.main();
    await tester.pumpAndSettle();
    expect(app.appId, startsWith('app_'));
    expect(app.appId, isNot('app_YOUR_APP_ID'), reason: 'pass the App ID');

    // Calls before configure log natively and do not crash.
    await tap(tester, 'Calls before configure');
    await until(
      tester,
      () => app.status.value != 'Ready',
      reason: 'preconfigure calls',
    );
    expect(app.status.value, 'Preconfigure calls completed');
    expect(Reception.isConfigured, isFalse);

    await tap(tester, 'Configure');
    await until(
      tester,
      () => app.status.value == 'Configured',
      reason: 'configure',
    );
    expect(Reception.isConfigured, isTrue);
    expect(Reception.usesRemoteAppearance, isFalse);
    expect(Reception.logLevel, ReceptionLogLevel.debug);
    expect(Reception.paywalls.map((paywall) => paywall.id), [
      'plans',
      'hidden',
    ]);
    await until(
      tester,
      () => available().contains('plans'),
      reason: 'plans available',
    );
    expect(available(), ['plans'], reason: '`hidden` is never offered');

    await tap(tester, 'Identify and metadata');
    await until(
      tester,
      () => app.status.value == 'Identity and metadata staged',
      reason: 'identify',
    );

    // Presented sheet: visibility reflects the actual chat.
    await tap(tester, 'Open chat');
    await until(
      tester,
      () => Reception.isChatOpen.value,
      reason: 'chat visible',
    );
    expect(app.events.value, contains('chatOpened'));
    await Reception.closeChat();
    await until(
      tester,
      () => !Reception.isChatOpen.value,
      reason: 'chat closed',
    );

    // Hanging availability fails closed after the 5 s native timeout.
    await tester.tap(find.text('Hanging availability'));
    await tester.pump();
    await Reception.refreshPaywalls(invalidate: true);
    await until(
      tester,
      () => available().isEmpty,
      timeout: const Duration(seconds: 12),
      reason: 'hanging availability fails closed',
    );
    await tester.tap(find.text('Hanging availability'));
    await tester.pump();
    await Reception.refreshPaywalls(invalidate: true);
    await until(
      tester,
      () => available().contains('plans'),
      reason: 'availability restored',
    );

    // Language override round trip.
    await tap(tester, 'German / app language');
    expect(Reception.languageOverride, 'de');
    await tap(tester, 'German / app language');
    expect(Reception.languageOverride, isNull);

    // Embedded chat in an Expanded.
    await tap(tester, 'Embedded chat');
    await tester.pumpAndSettle();
    expect(find.byType(ReceptionChatView), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ReceptionChatView), findsNothing);

    if (expectUnread) {
      await until(
        tester,
        () => Reception.unreadCount.value > 0,
        timeout: const Duration(seconds: 60),
        reason: 'unread count after a dashboard reply',
      );
    }
    final unread = Reception.unreadCount.value;

    // Hot-restart equivalent: Dart state is reset, native keeps running;
    // main() reconnects and re-reads state, callbacks are assigned again.
    resetReception();
    expect(Reception.isConfigured, isFalse);
    await app.main();
    await tester.pumpAndSettle();
    await tap(tester, 'Configure');
    await until(
      tester,
      () => app.status.value == 'Configured',
      reason: 'reconfigure after reset',
    );
    expect(Reception.isConfigured, isTrue);
    expect(Reception.unreadCount.value, unread);
    await Reception.refreshPaywalls(invalidate: true);
    await until(
      tester,
      () => available().contains('plans'),
      reason: 'availability after restart',
    );
    expect(available(), ['plans']);
    debugPrint('RESULT unread=$unread available=${available()}');
  });
}
