import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  /// Makes the next calls to [method] return the given futures in order.
  void reply(String method, List<Completer<SnapshotMessage>> replies) {
    final queue = [...replies];
    host.handlers[method] = (_) => queue.removeAt(0).future;
  }

  test('all setting getters reflect assignment before the host answers', () {
    for (final method in [
      'setAppearance',
      'setLanguageOverride',
      'setUpdatesAppBadge',
      'setLogLevel',
      'setPaywalls',
      'setUsesRemoteAppearance',
    ]) {
      host.handlers[method] = (_) => Completer<SnapshotMessage>().future;
    }
    Reception.appearance = const Appearance(
      accentColor: AppearanceColor.hex('#112233'),
    );
    Reception.languageOverride = 'de';
    Reception.updatesAppBadge = false;
    Reception.logLevel = LogLevel.debug;
    Reception.paywalls = [const ReceptionPaywall(id: 'plans', title: 'Plans')];
    Reception.usesRemoteAppearance = false;
    expect(Reception.appearance.toJson(), {'accentColor': '#112233'});
    expect(Reception.languageOverride, 'de');
    expect(Reception.updatesAppBadge, isFalse);
    expect(Reception.logLevel, LogLevel.debug);
    expect(Reception.paywalls, [
      const ReceptionPaywall(id: 'plans', title: 'Plans'),
    ]);
    expect(Reception.usesRemoteAppearance, isFalse);
  });

  test(
    'settings are sent with increasing revisions and native values',
    () async {
      Reception.appearance = const Appearance(title: 'Help');
      Reception.updatesAppBadge = false;
      Reception.usesRemoteAppearance = false;
      Reception.languageOverride = null;
      Reception.logLevel = LogLevel.off;
      await pumpEventQueue();
      expect(host.calls.map((call) => call.$1).toList(), [
        'connect',
        'setAppearance',
        'setUpdatesAppBadge',
        'setUsesRemoteAppearance',
        'setLanguageOverride',
        'setLogLevel',
      ]);
      expect(host.calls.skip(1).map((call) => call.$2), [
        ['{"title":"Help"}', 1],
        [false, 2],
        [false, 3],
        [null, 4],
        ['off', 5],
      ]);
    },
  );

  test(
    'events and an earlier response cannot overwrite a pending newer assignment',
    () async {
      final first = Completer<SnapshotMessage>();
      final second = Completer<SnapshotMessage>();
      reply('setAppearance', [first, second]);
      Reception.appearance = const Appearance(title: 'First');
      Reception.appearance = const Appearance(
        title: 'Second',
        fontFamily: 'Missing',
      );
      await pumpEventQueue();
      await host.send('onState', [snapshot(revision: 10, unreadCount: 3)]);
      expect(Reception.unreadCount.value, 3);
      expect(Reception.appearance.title, 'Second');
      first.complete(
        snapshot(
          revision: 11,
          settingRevisions: {'appearance': 1},
          appearanceJson: '{"title":"First"}',
        ),
      );
      await pumpEventQueue();
      expect(Reception.appearance.toJson(), {
        'title': 'Second',
        'fontFamily': 'Missing',
      });
      second.complete(
        snapshot(
          revision: 12,
          settingRevisions: {'appearance': 2},
          appearanceJson: '{"title":"Second"}',
        ),
      );
      await pumpEventQueue();
      expect(Reception.appearance.toJson(), {'title': 'Second'});
    },
  );

  test('out-of-order responses keep the latest acknowledged value', () async {
    final first = Completer<SnapshotMessage>();
    final second = Completer<SnapshotMessage>();
    reply('setLanguageOverride', [first, second]);
    Reception.languageOverride = 'de';
    Reception.languageOverride = 'fr';
    await pumpEventQueue();
    second.complete(
      snapshot(
        revision: 12,
        settingRevisions: {'languageOverride': 2},
        languageOverride: 'fr',
      ),
    );
    await pumpEventQueue();
    first.complete(
      snapshot(
        revision: 11,
        settingRevisions: {'languageOverride': 1},
        languageOverride: 'de',
      ),
    );
    await pumpEventQueue();
    expect(Reception.languageOverride, 'fr');
  });

  test(
    'settings reconcile independently when another property is still pending',
    () async {
      final appearance = Completer<SnapshotMessage>();
      final language = Completer<SnapshotMessage>();
      reply('setAppearance', [appearance]);
      reply('setLanguageOverride', [language]);
      Reception.appearance = const Appearance(fontFamily: 'Missing');
      Reception.languageOverride = 'de';
      await pumpEventQueue();
      appearance.complete(
        snapshot(revision: 10, settingRevisions: {'appearance': 1}),
      );
      await pumpEventQueue();
      expect(Reception.appearance.toJson(), isEmpty);
      expect(Reception.languageOverride, 'de');
    },
  );

  test(
    'failure restores confirmed state but cannot discard a newer assignment',
    () async {
      final first = Completer<SnapshotMessage>();
      final second = Completer<SnapshotMessage>();
      reply('setLogLevel', [first, second]);
      Reception.logLevel = LogLevel.debug;
      Reception.logLevel = LogLevel.off;
      await pumpEventQueue();
      first.completeError(Exception('private native diagnostic'));
      await pumpEventQueue();
      expect(Reception.logLevel, LogLevel.off);
      second.completeError(Exception('private native diagnostic'));
      await pumpEventQueue();
      expect(Reception.logLevel, LogLevel.info);
      expect(logs, List.filled(2, '[Reception] Native bridge call failed.'));
    },
  );

  test(
    'invalid appearance fields keep their previous value end to end',
    () async {
      Reception.appearance = const Appearance(
        accentColor: AppearanceColor.hex('#112233'),
        title: 'Old',
      );
      Reception.appearance = const Appearance(
        accentColor: AppearanceColor.hex('red'),
        welcomeIconSize: 200,
      );
      expect(Reception.appearance.toJson(), {'accentColor': '#112233'});
      expect(logs, [
        '[Reception] Invalid appearance.accentColor; ignored.',
        '[Reception] Invalid appearance.welcomeIconSize; ignored.',
      ]);
      await pumpEventQueue();
      expect(jsonDecode(host.callsTo('setAppearance').last[0]! as String), {
        'accentColor': '#112233',
      });
    },
  );
}
