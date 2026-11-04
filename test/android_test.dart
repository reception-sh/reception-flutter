import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reception_flutter/reception_flutter.dart';
import 'package:reception_flutter/src/android_sdk_version.dart';
import 'package:reception_flutter/src/reception.dart' show resetReception;

import 'fake_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeHost host;
  late List<String> logs;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    resetReception();
    host = FakeHost();
    logs = captureLogs();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('uses the host like iOS and reports the Android SDK version', () async {
    expect(Reception.version, androidSdkVersion);
    await Reception.configure(appId: 'app_example');
    await Reception.openChat();
    expect(Reception.isConfigured, isTrue);
    expect(host.callsTo('configure'), [
      ['app_example', true, null],
    ]);
    expect(host.callsTo('openChat'), hasLength(1));
    expect(logs, isEmpty);
  });

  test('configure passes a valid notification small icon name', () async {
    await Reception.configure(
      appId: 'app_example',
      android: const ReceptionAndroidOptions(
        notificationSmallIcon: 'ic_notification',
      ),
    );
    final longest = 'a${'b' * 63}';
    await Reception.configure(
      appId: 'app_example',
      android: ReceptionAndroidOptions(notificationSmallIcon: longest),
    );
    await Reception.configure(
      appId: 'app_example',
      android: const ReceptionAndroidOptions(),
    );
    expect(host.callsTo('configure'), [
      ['app_example', true, 'ic_notification'],
      ['app_example', true, longest],
      ['app_example', true, null],
    ]);
    expect(logs, isEmpty);
  });

  test(
    'an invalid notification small icon warns and keeps the default',
    () async {
      const invalid = [
        '',
        'Ic_notification',
        '1icon',
        '_icon',
        'ic-notification',
        'ic.png',
      ];
      for (final name in [...invalid, 'a' * 65]) {
        await Reception.configure(
          appId: 'app_example',
          android: ReceptionAndroidOptions(notificationSmallIcon: name),
        );
      }
      expect(
        host.callsTo('configure'),
        List.filled(7, ['app_example', true, null]),
      );
      expect(logs, hasLength(7));
      expect(
        logs,
        everyElement(
          '[Reception] Invalid android.notificationSmallIcon; ignored.',
        ),
      );
    },
  );

  test('the Android SDK version matches the Gradle dependency', () {
    final gradle = File('android/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('"sh.reception:reception:$androidSdkVersion"'));
  });

  test('push tokens are FCM registration tokens', () async {
    const token = 'dQw4w9WgXcQ:APA91bH-abc_DEF123';
    await Reception.setPushToken(
      token,
      environment: ReceptionPushEnvironment.sandbox,
    );
    for (final invalid in ['', 'has space', 'ExpoPushToken[x]', 'a' * 4097]) {
      await Reception.setPushToken(invalid);
    }
    // FCM tokens are case-sensitive, so they are passed unchanged.
    expect(host.callsTo('setPushToken'), [
      [token, 'sandbox'],
    ]);
    expect(logs, hasLength(4));
    expect(logs, everyElement('[Reception] Invalid FCM token; ignored.'));
  });

  test('push recognizes FCM data and the iOS envelope', () async {
    expect(
      await Reception.handlePushNotification({'reception': 'thread'}),
      isTrue,
    );
    expect(
      await Reception.handlePushNotification({
        'reception': {'conversationId': 'other'},
      }, openChat: false),
      isTrue,
    );
    expect(await Reception.handlePushNotification({'reception': ''}), isFalse);
    expect(await Reception.handlePushNotification({'title': 'Hi'}), isFalse);
    expect(host.callsTo('handlePushNotification'), [
      ['thread', true],
      ['other', false],
    ]);
  });
}
