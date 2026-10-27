import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reception_flutter/reception_flutter.dart';
import 'package:reception_flutter/src/reception.dart' show resetReception;
import 'package:reception_flutter/testing.dart';

import 'fake_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeHost host;
  setUp(() {
    resetReception();
    host = FakeHost();
    captureLogs();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('configures through the lazy connection and hydrates state', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    host.handlers['configureForTesting'] = (_) =>
        snapshot(revision: 2, isConfigured: true);
    await configureReceptionForTesting(
      appId: 'app_example',
      serviceUrl: Uri.parse('http://localhost:3000'),
    );
    expect(Reception.isConfigured, isTrue);
    expect(host.calls.map((call) => call.$1), [
      'connect',
      'configureForTesting',
    ]);
    expect(host.callsTo('configureForTesting').single, [
      'app_example',
      'http://localhost:3000',
    ]);
  });

  test('is a no-op off iOS', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await configureReceptionForTesting(
      appId: 'app_example',
      serviceUrl: Uri.parse('http://localhost:3000'),
    );
    expect(Reception.isConfigured, isFalse);
    expect(host.calls, isEmpty);
  });
}
