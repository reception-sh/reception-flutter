import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reception_flutter/reception_flutter.dart';

import 'fake_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
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
        Reception.opensWebLinksInApp = false;
        Reception.languageOverride = 'de';
        Reception.logLevel = ReceptionLogLevel.off;
        Reception.paywalls = [ReceptionPaywall(id: 'plans', title: 'Plans')];
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
        expect(Reception.opensWebLinksInApp, isTrue);
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
          platform == TargetPlatform.macOS
              ? ['[Reception] Support chat is available on iOS and Android only.']
              : isEmpty,
        );
      },
    );
  }

  testWidgets('ReceptionChatView renders nothing off iOS and Android', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(const ReceptionChatView());
    expect(find.byType(SizedBox), findsOneWidget);
    expect(find.byType(UiKitView), findsNothing);
    expect(find.byType(PlatformViewLink), findsNothing);
    debugDefaultTargetPlatformOverride = null;
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

  testWidgets('ReceptionChatView hosts the native chat on Android with '
      'hybrid composition', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final created = <Map<Object?, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        if (call.method == 'create') {
          created.add(call.arguments as Map<Object?, Object?>);
        }
        return null;
      },
    );
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ReceptionChatView(),
      ),
    );
    await tester.pump();
    expect(find.byType(PlatformViewLink), findsOneWidget);
    expect(created, [
      allOf(
        containsPair('viewType', 'reception_flutter/chat'),
        containsPair('hybrid', true),
      ),
    ]);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('ReceptionChatView claims vertical drags by default', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async => null,
    );
    Set<Factory<OneSequenceGestureRecognizer>> recognizers() => tester
        .widget<AndroidViewSurface>(find.byType(AndroidViewSurface))
        .gestureRecognizers;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListView(
          children: const [SizedBox(height: 400, child: ReceptionChatView())],
        ),
      ),
    );
    await tester.pump();
    final defaults = recognizers();
    expect(defaults, ReceptionChatView.defaultGestureRecognizers);
    expect(defaults.map((factory) => factory.constructor()), [
      isA<VerticalDragGestureRecognizer>(),
    ]);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ReceptionChatView(gestureRecognizers: {}),
      ),
    );
    await tester.pump();
    expect(recognizers(), isEmpty);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ReceptionChatView(),
      ),
    );
    expect(
      tester.widget<UiKitView>(find.byType(UiKitView)).gestureRecognizers,
      ReceptionChatView.defaultGestureRecognizers,
    );
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('ReceptionChatView applies changed gestureRecognizers on Android '
      'without recreating the native view', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var creations = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        if (call.method == 'create') creations += 1;
        return null;
      },
    );
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    Future<void> show(Set<Factory<OneSequenceGestureRecognizer>> recognizers) =>
        tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: ListView(
              controller: scroll,
              children: [
                SizedBox(
                  height: 400,
                  child: ReceptionChatView(gestureRecognizers: recognizers),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        );
    Future<void> dragChat() async {
      scroll.jumpTo(0);
      await tester.drag(find.byType(ReceptionChatView), const Offset(0, -200));
      await tester.pumpAndSettle();
    }

    await show(ReceptionChatView.defaultGestureRecognizers);
    await tester.pump();
    await dragChat();
    expect(scroll.offset, 0, reason: 'the chat claims the drag');

    await show(const {});
    await dragChat();
    expect(scroll.offset, greaterThan(0), reason: 'the list takes the drag');

    await show(ReceptionChatView.defaultGestureRecognizers);
    await dragChat();
    expect(scroll.offset, 0, reason: 'the chat claims the drag again');

    expect(creations, 1);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
