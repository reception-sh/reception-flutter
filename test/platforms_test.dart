import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reception_flutter/reception_flutter.dart';

import 'fake_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    test(
      '$platform never touches the host, throws, or changes default state',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final host = FakeHost();
        final logs = captureLogs();
        await Reception.configure(appId: 'test');
        await Reception.openChat();
        await Reception.closeChat();
        await Reception.track('paywall_declined', opensChat: true);
        await Reception.identify(const ReceptionIdentity.user(userId: 'test'));
        await Reception.identify(const ReceptionIdentity.token('token'));
        await Reception.setMetadata({'plan': 'test'});
        await Reception.setPushToken('abcd');
        await Reception.registerForPushIfAuthorized();
        await Reception.deleteData();
        await Reception.logout();
        await Reception.refreshPaywalls();
        expect(
          await Reception.handlePushNotification({
            'reception': {'conversationId': 'id'},
          }),
          isFalse,
        );
        Reception.appearance = const ReceptionAppearance(
          accentColor: ReceptionColor.hex('#ff0000'),
        );
        Reception.updatesAppBadge = false;
        Reception.usesRemoteAppearance = false;
        Reception.languageOverride = 'de';
        Reception.logLevel = ReceptionLogLevel.off;
        Reception.paywalls = [
          const ReceptionPaywall(id: 'plans', title: 'Plans'),
        ];
        Reception.onEvent = (_) {};
        Reception.onPaywall = (_) {};
        Reception.paywallAvailability = (_) => true;
        await pumpEventQueue();
        expect(Reception.isConfigured, isFalse);
        expect(Reception.isChatOpen.value, isFalse);
        expect(Reception.unreadCount.value, 0);
        expect(Reception.availablePaywalls.value, isEmpty);
        expect(Reception.appearance.toJson(), isEmpty);
        expect(Reception.updatesAppBadge, isTrue);
        expect(Reception.usesRemoteAppearance, isTrue);
        expect(Reception.languageOverride, isNull);
        expect(Reception.logLevel, ReceptionLogLevel.info);
        expect(Reception.paywalls, isEmpty);
        expect(Reception.onEvent, isNull);
        expect(Reception.onPaywall, isNull);
        expect(Reception.paywallAvailability, isNull);
        expect(Reception.version, isNotEmpty);
        expect(host.calls, isEmpty);
        // The notice is logged once per process, so only by the first platform.
        expect(
          logs,
          platform == TargetPlatform.android
              ? ['[Reception] Support chat is available on iOS only.']
              : isEmpty,
        );
      },
    );
  }

  testWidgets('ReceptionChatView renders nothing off iOS', (tester) async {
    await tester.pumpWidget(const ReceptionChatView());
    expect(find.byType(SizedBox), findsOneWidget);
    expect(find.byType(UiKitView), findsNothing);
  });

  testWidgets('ReceptionChatView hosts the native chat on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final created = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        if (call.method == 'create') created.add(call.arguments);
        return null;
      },
    );
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ReceptionChatView(),
      ),
    );
    expect(find.byType(UiKitView), findsOneWidget);
    expect(created, [containsPair('viewType', 'reception_flutter/chat')]);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
