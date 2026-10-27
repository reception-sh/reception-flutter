import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reception_flutter/reception_flutter.dart';
import 'package:reception_flutter/src/messages.g.dart';
import 'package:reception_flutter/src/reception.dart' show resetReception;

import 'fake_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeHost host;
  late List<String> logs;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    resetReception();
    host = FakeHost();
    logs = captureLogs();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('connects lazily, once, before the first host call', () async {
    expect(Reception.isConfigured, isFalse);
    expect(Reception.version, '1.6.0');
    expect(host.calls, isEmpty);
    await Reception.openChat();
    await Reception.closeChat();
    expect(host.calls.map((call) => call.$1), [
      'connect',
      'openChat',
      'closeChat',
    ]);
  });

  test(
    'configuration hydrates state and host errors become typed errors',
    () async {
      expect(Reception.isConfigured, isFalse);
      await Reception.configure(appId: 'app_example');
      expect(Reception.isConfigured, isTrue);
      expect(host.callsTo('configure'), [
        ['app_example', true],
      ]);
      await Reception.configure(
        appId: 'app_example',
        handlesNotifications: false,
      );
      expect(host.callsTo('configure').last, ['app_example', false]);
      host.handlers['openChat'] = (_) =>
          throw PlatformException(code: 'error', message: 'private diagnostic');
      await expectLater(
        Reception.openChat(),
        throwsA(const ReceptionError('bridge_error', 0)),
      );
    },
  );

  test(
    'identity variants, metadata and push forward only valid inputs',
    () async {
      await Reception.identify(
        const Identity.user(userId: 'customer', name: 'Test'),
      );
      await Reception.identify(const Identity.token('signed-token'));
      await Reception.setMetadata({'plan': 'Pro'});
      await Reception.setPushToken(
        'AABB01',
        environment: PushEnvironment.sandbox,
      );
      expect(host.callsTo('identify'), [
        ['customer', 'Test', null],
      ]);
      expect(host.callsTo('identifyToken'), [
        ['signed-token'],
      ]);
      expect(host.callsTo('setMetadata'), [
        [
          {'plan': 'Pro'},
        ],
      ]);
      expect(host.callsTo('setPushToken'), [
        ['aabb01', 'sandbox'],
      ]);
      for (final token in ['', 'a', 'gg', 'ExpoPushToken[x]', 'a' * 514]) {
        await Reception.setPushToken(token);
      }
      expect(host.callsTo('setPushToken'), hasLength(1));
      expect(
        logs,
        everyElement('[Reception] Invalid APNs token or environment; ignored.'),
      );
      expect(logs, hasLength(5));
      expect(logs.join(), isNot(contains('signed-token')));
      await Reception.setPushToken('ab' * 256);
      await Reception.registerForPushIfAuthorized();
      expect(host.callsTo('setPushToken').last, ['ab' * 256, 'automatic']);
      expect(host.callsTo('registerForPushIfAuthorized'), hasLength(1));
    },
  );

  test(
    'push recognizes the SDK routing envelope and ignores unrelated payloads',
    () async {
      expect(await Reception.handlePushNotification({'aps': {}}), isFalse);
      expect(
        await Reception.handlePushNotification({
          'reception': {'conversationId': ''},
        }),
        isFalse,
      );
      expect(
        await Reception.handlePushNotification({'reception': 'thread'}),
        isFalse,
      );
      expect(host.callsTo('handlePushNotification'), isEmpty);
      expect(
        await Reception.handlePushNotification(<String, Object?>{
          'reception': <Object?, Object?>{'conversationId': 'thread'},
          'aps': {},
        }, openChat: false),
        isTrue,
      );
      expect(host.callsTo('handlePushNotification'), [
        ['thread', false],
      ]);
      await Reception.handlePushNotification({
        'reception': {'conversationId': 'thread'},
      });
      expect(host.callsTo('handlePushNotification').last, ['thread', true]);
    },
  );

  test('track forwards events', () async {
    await Reception.track('paywall_declined');
    await Reception.track('paywall_declined', opensChat: true);
    expect(host.callsTo('track'), [
      ['paywall_declined', false],
      ['paywall_declined', true],
    ]);
  });

  test(
    'logout and deletion update state; deletion preserves code and HTTP status',
    () async {
      await Reception.configure(appId: 'app_example');
      host.handlers['deleteData'] = (_) => DeleteResultMessage(
        state: snapshot(revision: 5),
        error: ErrorMessage(code: 'delete_failed', status: 503),
      );
      await expectLater(
        Reception.deleteData(),
        throwsA(const ReceptionError('delete_failed', 503)),
      );
      expect(Reception.isConfigured, isFalse);
      host.handlers['deleteData'] = (_) =>
          DeleteResultMessage(state: snapshot(revision: 6, isConfigured: true));
      await Reception.deleteData();
      expect(Reception.isConfigured, isTrue);
      host.handlers['logout'] = (_) => snapshot(revision: 7);
      await Reception.logout();
      expect(Reception.isConfigured, isFalse);
    },
  );

  test(
    'live state notifies changes, unsubscribes, and ignores stale snapshots',
    () async {
      final counts = <int>[];
      final open = <bool>[];
      void count() => counts.add(Reception.unreadCount.value);
      Reception.unreadCount.addListener(count);
      Reception.isChatOpen.addListener(
        () => open.add(Reception.isChatOpen.value),
      );
      await Reception.openChat();
      await host.send('onState', [
        snapshot(revision: 10, unreadCount: 3, isChatOpen: true),
      ]);
      expect(counts, [3]);
      expect(open, [true]);
      await host.send('onState', [snapshot(revision: 2)]);
      expect(Reception.unreadCount.value, 3);
      Reception.unreadCount.removeListener(count);
      await host.send('onState', [snapshot(revision: 11)]);
      expect(counts, [3]);
      expect(open, [true, false]);
    },
  );

  test('available paywalls notify only when their content changes', () async {
    final updates = <List<ReceptionPaywall>>[];
    Reception.availablePaywalls.addListener(
      () => updates.add(Reception.availablePaywalls.value),
    );
    await Reception.openChat();
    PaywallMessage plans() => PaywallMessage(
      id: 'plans',
      title: 'Plans',
      products: [PaywallProductMessage(id: 'pro', price: r'$5')],
      presentable: true,
    );
    await host.send('onState', [
      snapshot(revision: 2, availablePaywalls: [plans()]),
    ]);
    await host.send('onState', [
      snapshot(revision: 3, availablePaywalls: [plans()], unreadCount: 1),
    ]);
    expect(updates, [
      [
        const ReceptionPaywall(
          id: 'plans',
          title: 'Plans',
          products: [ReceptionPaywallProduct(id: 'pro', price: r'$5')],
        ),
      ],
    ]);
  });

  test(
    'events map every type, preserve typed identity rejection and handler replacement',
    () async {
      final first = <ReceptionEvent>[];
      final next = <ReceptionEvent>[];
      Reception.onEvent = first.add;
      Reception.onEvent = next.add;
      await Reception.openChat();
      await host.send('onEvent', [
        EventMessage(
          type: 'identityRejected',
          error: ErrorMessage(code: 'identity_token_expired', status: 401),
        ),
      ]);
      for (final type in [
        'chatOpened',
        'messageSent',
        'imageSent',
        'reviewOpened',
        'paywallOpened',
        'dataDeleted',
        'identityRejected',
        'unknown',
      ]) {
        await host.send('onEvent', [EventMessage(type: type)]);
      }
      expect(first, isEmpty);
      expect(next.first, isA<IdentityRejectedEvent>());
      expect(
        (next.first as IdentityRejectedEvent).error,
        const ReceptionError('identity_token_expired', 401),
      );
      expect(next.skip(1).map((event) => event.runtimeType), [
        ChatOpenedEvent,
        MessageSentEvent,
        ImageSentEvent,
        ReviewOpenedEvent,
        PaywallOpenedEvent,
        DataDeletedEvent,
      ]);
      Reception.onEvent = null;
      expect(Reception.onEvent, isNull);
      await host.send('onEvent', [EventMessage(type: 'messageSent')]);
      expect(next, hasLength(7));
    },
  );

  test(
    'paywall availability round trip, failure, replacement and stale generations fail closed',
    () async {
      Future<Object?> check(int generation) =>
          host.send('checkPaywallAvailability', ['plans', generation]);
      await Reception.openChat();
      expect(await check(0), isFalse, reason: 'no callback');
      Reception.paywallAvailability = (id) async => id == 'plans';
      expect(await check(1), isTrue);
      Reception.paywallAvailability = (_) =>
          throw StateError('private details');
      expect(await check(2), isFalse);
      expect(logs, [
        '[Reception] Paywall availability callback failed; offer unavailable.',
      ]);
      final pending = Completer<bool>();
      Reception.paywallAvailability = (_) => pending.future;
      final replaced = check(3);
      await pumpEventQueue();
      Reception.paywallAvailability = null;
      pending.complete(true);
      expect(await replaced, isFalse);
      final again = Completer<bool>();
      Future<bool> wait(String _) => again.future;
      // One tear-off, so the handler stays identical across both assignments.
      final same = wait;
      Reception.paywallAvailability = same;
      final reassigned = check(5);
      await pumpEventQueue();
      Reception.paywallAvailability = same;
      again.complete(true);
      expect(
        await reassigned,
        isFalse,
        reason: 'same callback, new generation',
      );
      Reception.paywallAvailability = (_) => true;
      expect(await check(1), isFalse, reason: 'stale generation');
      expect(await check(7), isTrue);
      expect(host.callsTo('setPaywallAvailability'), [
        [true, 1],
        [true, 2],
        [true, 3],
        [false, 4],
        [true, 5],
        [true, 6],
        [true, 7],
      ]);
    },
  );

  test(
    'paywall callbacks and registrations forward without closing chat',
    () async {
      final opened = <String>[];
      Reception.onPaywall = opened.add;
      Reception.paywalls = [
        const ReceptionPaywall(id: 'plans', title: 'Plans'),
      ];
      await host.send('onPaywall', ['plans']);
      expect(opened, ['plans']);
      Reception.onPaywall = null;
      await host.send('onPaywall', ['plans']);
      expect(opened, ['plans']);
      expect(host.callsTo('setPaywallHandler'), [
        [true],
        [false],
      ]);
      expect(host.callsTo('closeChat'), isEmpty);
      await Reception.refreshPaywalls(invalidate: true);
      await Reception.refreshPaywalls();
      expect(host.callsTo('refreshPaywalls'), [
        [true],
        [false],
      ]);
    },
  );

  test('paywall details pass through to the host', () async {
    const detailed = [
      ReceptionPaywall(
        id: 'plans',
        title: 'Plans',
        source: 'revenuecat',
        products: [
          ReceptionPaywallProduct(
            id: 'pro_yearly',
            price: r'$59.99',
            period: 'P1Y',
            trial: 'P1W',
          ),
        ],
      ),
      ReceptionPaywall(id: 'legacy', title: 'Legacy', presentable: false),
    ];
    Reception.paywalls = detailed;
    expect(Reception.paywalls, detailed);
    await pumpEventQueue();
    expect(host.callsTo('setPaywalls').single[0], [
      PaywallMessage(
        id: 'plans',
        title: 'Plans',
        source: 'revenuecat',
        products: [
          PaywallProductMessage(
            id: 'pro_yearly',
            price: r'$59.99',
            period: 'P1Y',
            trial: 'P1W',
          ),
        ],
        presentable: true,
      ),
      PaywallMessage(
        id: 'legacy',
        title: 'Legacy',
        products: [],
        presentable: false,
      ),
    ]);
    expect(Reception.paywalls, detailed);
  });

  test(
    'a hot restart reconnects and stops answering for the old callbacks',
    () async {
      Reception.paywallAvailability = (_) => true;
      await pumpEventQueue();
      resetReception();
      expect(
        await host.send('checkPaywallAvailability', ['plans', 1]),
        isFalse,
      );
      await Reception.openChat();
      expect(host.callsTo('connect'), hasLength(2));
    },
  );
}
