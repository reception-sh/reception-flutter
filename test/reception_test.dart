import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reception_flutter/reception_flutter.dart';
import 'package:reception_flutter/src/sdk_version.dart';
import 'package:reception_flutter/src/messages.g.dart';
import 'package:reception_flutter/src/reception.dart' show resetReception;

import 'fake_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeHost host;
  late List<String> logs;
  late List<FlutterErrorDetails> errors;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    resetReception();
    host = FakeHost();
    logs = captureLogs();
    errors = captureErrors();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('connects lazily, once, before the first host call', () async {
    expect(Reception.isConfigured, isFalse);
    expect(Reception.version, sdkVersion);
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
        const ReceptionIdentity.user(userId: 'customer', name: 'Test'),
      );
      await Reception.identify(const ReceptionIdentity.token('signed-token'));
      await Reception.setMetadata({'plan': 'Pro'});
      await Reception.setPushToken(
        'AABB01',
        environment: ReceptionPushEnvironment.sandbox,
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
        ReceptionPaywall(
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
        'linkOpened',
        'dataDeleted',
        'identityRejected',
        'unknown',
      ]) {
        await host.send('onEvent', [EventMessage(type: type)]);
      }
      expect(first, isEmpty);
      expect(next.first, isA<ReceptionIdentityRejected>());
      expect(
        (next.first as ReceptionIdentityRejected).error,
        const ReceptionError('identity_token_expired', 401),
      );
      expect(next.skip(1).map((event) => event.runtimeType), [
        ReceptionChatOpened,
        ReceptionMessageSent,
        ReceptionImageSent,
        ReceptionReviewOpened,
        ReceptionPaywallOpened,
        ReceptionLinkOpened,
        ReceptionDataDeleted,
      ]);
      Reception.onEvent = null;
      expect(Reception.onEvent, isNull);
      await host.send('onEvent', [EventMessage(type: 'messageSent')]);
      expect(next, hasLength(8));
    },
  );

  /// Sends a host availability request for `plans`.
  Future<void> request(String requestId, int generation) =>
      host.send('requestPaywallAvailability', [requestId, 'plans', generation]);

  /// The answer Dart resolved for [requestId], or null if still pending.
  Future<Object?> resolution(String requestId) async {
    await pumpEventQueue();
    final answers = [
      for (final args in host.callsTo('resolvePaywallAvailability'))
        if (args[0] == requestId) args[1],
    ];
    expect(answers.length, lessThan(2));
    return answers.firstOrNull;
  }

  Future<Object?> check(String requestId, int generation) async {
    await request(requestId, generation);
    return resolution(requestId);
  }

  test(
    'paywall availability round trip, failure, replacement and stale generations fail closed',
    () async {
      await Reception.openChat();
      expect(await check('none', 0), isFalse, reason: 'no callback');
      Reception.paywallAvailability = (id) async => id == 'plans';
      expect(await check('a', 1), isTrue);
      Reception.paywallAvailability = (_) =>
          throw StateError('private details');
      expect(await check('b', 2), isFalse);
      expect(errors.single.exception, isA<StateError>());
      expect(errors.single.library, 'reception_flutter');
      expect(logs, isEmpty);
      final pending = Completer<bool>();
      Reception.paywallAvailability = (_) => pending.future;
      await request('c', 3);
      expect(await resolution('c'), isNull);
      Reception.paywallAvailability = null;
      pending.complete(true);
      expect(await resolution('c'), isFalse);
      final again = Completer<bool>();
      Future<bool> wait(String _) => again.future;
      // One tear-off, so the handler stays identical across both assignments.
      final same = wait;
      Reception.paywallAvailability = same;
      await request('d', 5);
      await pumpEventQueue();
      Reception.paywallAvailability = same;
      again.complete(true);
      expect(
        await resolution('d'),
        isFalse,
        reason: 'same callback, new generation',
      );
      final asked = <String>[];
      Reception.paywallAvailability = (id) {
        asked.add(id);
        return true;
      };
      expect(await check('e', 1), isFalse, reason: 'stale generation');
      expect(asked, isEmpty, reason: 'stale requests never reach the app');
      expect(await check('f', 7), isTrue);
      expect(asked, ['plans']);
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
    'availability is resolved even when the host rejects the answer',
    () async {
      Reception.paywallAvailability = (_) => true;
      host.handlers['resolvePaywallAvailability'] = (_) =>
          throw PlatformException(code: 'error');
      expect(await check('a', 1), isTrue);
      expect(logs, ['[Reception] Native bridge call failed.']);
    },
  );

  test(
    'paywall callbacks and registrations forward without closing chat',
    () async {
      final opened = <String>[];
      Reception.onPaywall = opened.add;
      Reception.paywalls = [ReceptionPaywall(id: 'plans', title: 'Plans')];
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

  test('screens are validated, reported by ID and value, and opened', () async {
    final opened = <String>[];
    Reception.screens = [
      ReceptionScreen('settings', onOpen: () => opened.add('settings')),
      ReceptionScreen.withValue(
        'order',
        value: 'Order number',
        onOpenWithValue: (number) => opened.add('order $number'),
      ),
      ReceptionScreen('settings', onOpen: () => opened.add('duplicate')),
    ];
    await pumpEventQueue();
    expect(Reception.screens.map((screen) => screen.id), ['settings', 'order']);
    final sent = host.callsTo('setScreens').single.single! as List<Object?>;
    expect(
      sent.cast<ScreenMessage>().map((screen) => (screen.id, screen.value)),
      [('settings', null), ('order', 'Order number')],
    );
    await host.send('onScreen', ['settings', null]);
    await host.send('onScreen', ['order', '42']);
    await host.send('onScreen', ['order', null]);
    await host.send('onScreen', ['gone', null]);
    expect(opened, ['settings', 'order 42']);
    final logs = captureLogs();
    Reception.screens = [ReceptionScreen('bad id', onOpen: () {})];
    Reception.screens = [
      ReceptionScreen.withValue('x', value: ' ', onOpenWithValue: (_) {}),
    ];
    await pumpEventQueue();
    expect(logs, hasLength(2));
    expect(Reception.screens.map((screen) => screen.id), ['settings', 'order']);
    expect(host.callsTo('setScreens'), hasLength(1));
    Reception.screens = const [];
    await pumpEventQueue();
    expect(host.callsTo('setScreens').last, [<Object?>[]]);
  });

  test('paywall details pass through to the host', () async {
    final detailed = [
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
      expect(await check('old', 1), isFalse);
      await Reception.openChat();
      expect(host.callsTo('connect'), hasLength(2));
    },
  );

  test('a failed connect is retried by the next call', () async {
    var attempts = 0;
    host.handlers['connect'] = (_) => ++attempts == 1
        ? throw PlatformException(code: 'channel-error')
        : snapshot();
    await expectLater(
      Reception.openChat(),
      throwsA(const ReceptionError('bridge_error', 0)),
    );
    Reception.logLevel = ReceptionLogLevel.debug;
    await pumpEventQueue();
    expect(host.callsTo('setLogLevel'), hasLength(1));
    await Reception.openChat();
    expect(host.calls.map((call) => call.$1), [
      'connect',
      'connect',
      'setLogLevel',
      'openChat',
    ]);
    expect(Reception.logLevel, ReceptionLogLevel.debug);
  });

  test(
    'concurrent first calls share one connect and keep their order',
    () async {
      final connected = Completer<SnapshotMessage>();
      host.handlers['connect'] = (_) => connected.future;
      final calls = [
        Reception.openChat(),
        Reception.track('first'),
        Reception.closeChat(),
      ];
      Reception.updatesAppBadge = false;
      await pumpEventQueue();
      expect(host.calls.map((call) => call.$1), ['connect']);
      connected.complete(snapshot());
      await Future.wait(calls);
      await pumpEventQueue();
      expect(host.calls.map((call) => call.$1), [
        'connect',
        'openChat',
        'track',
        'closeChat',
        'setUpdatesAppBadge',
      ]);
    },
  );

  test(
    'setting payloads are captured at assignment, before the connection resolves',
    () async {
      final connected = Completer<SnapshotMessage>();
      host.handlers['connect'] = (_) => connected.future;
      final list = [ReceptionPaywall(id: 'plans', title: 'Plans')];
      Reception.paywalls = list;
      list.clear();
      connected.complete(snapshot());
      await pumpEventQueue();
      expect(host.callsTo('setPaywalls').single[0], [
        PaywallMessage(
          id: 'plans',
          title: 'Plans',
          products: [],
          presentable: true,
        ),
      ]);
      expect(Reception.paywalls, [
        ReceptionPaywall(id: 'plans', title: 'Plans'),
      ]);
    },
  );

  test(
    'throwing app callbacks are reported and never reach the host as errors',
    () async {
      Reception.onEvent = (_) => throw StateError('event failed');
      Reception.onPaywall = (_) => throw StateError('paywall failed');
      await Reception.openChat();
      // FakeHost.send throws if Dart replied with an error.
      await host.send('onEvent', [EventMessage(type: 'chatOpened')]);
      await host.send('onPaywall', ['plans']);
      expect(errors.map((error) => '${error.exception}'), [
        'Bad state: event failed',
        'Bad state: paywall failed',
      ]);
      expect(
        errors.map((error) => error.library),
        everyElement('reception_flutter'),
      );
    },
  );

  test('paywalls are frozen at assignment', () async {
    final products = [const ReceptionPaywallProduct(id: 'pro')];
    Reception.paywalls = [
      ReceptionPaywall(id: 'plans', title: 'Plans', products: products),
    ];
    products.add(const ReceptionPaywallProduct(id: 'later'));
    await pumpEventQueue();
    expect(Reception.paywalls.single.products, [
      const ReceptionPaywallProduct(id: 'pro'),
    ]);
    expect(
      () => Reception.paywalls.single.products.add(products.last),
      throwsUnsupportedError,
    );
    final sent = host.callsTo('setPaywalls').single[0]! as List<Object?>;
    expect((sent.single! as PaywallMessage).products, hasLength(1));
  });

  test('metadata and push payloads are read at call time', () async {
    final connected = Completer<SnapshotMessage>();
    host.handlers['connect'] = (_) => connected.future;
    final metadata = {'plan': 'Pro'};
    final routing = <String, Object?>{'conversationId': 'thread'};
    final calls = [
      Reception.setMetadata(metadata),
      Reception.handlePushNotification({'reception': routing}),
    ];
    metadata['plan'] = 'Free';
    routing['conversationId'] = 'other';
    connected.complete(snapshot());
    await Future.wait(calls);
    expect(host.callsTo('setMetadata').single, [
      {'plan': 'Pro'},
    ]);
    expect(host.callsTo('handlePushNotification').single, ['thread', true]);
  });

  test('a paywall keeps its products when the passed list changes later', () {
    final products = [const ReceptionPaywallProduct(id: 'pro')];
    final paywall = ReceptionPaywall(
      id: 'plans',
      title: 'Plans',
      products: products,
    );
    final same = ReceptionPaywall(
      id: 'plans',
      title: 'Plans',
      products: const [ReceptionPaywallProduct(id: 'pro')],
    );
    final hash = paywall.hashCode;
    products.add(const ReceptionPaywallProduct(id: 'later'));
    expect(paywall.products, [const ReceptionPaywallProduct(id: 'pro')]);
    expect(paywall, same);
    expect(paywall.hashCode, hash);
    expect(() => paywall.products.add(products.last), throwsUnsupportedError);
  });
}
