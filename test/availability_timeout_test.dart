import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reception_flutter/reception_flutter.dart';

import 'fake_host.dart';

void main() {
  testWidgets(
    'a paywall availability callback that never completes resolves false after 5 s',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final host = FakeHost();
      Reception.paywallAvailability = (_) => Completer<bool>().future;
      await tester.pump();
      await host.send('requestPaywallAvailability', ['request', 'plans', 1]);
      await tester.pump(const Duration(seconds: 4));
      expect(host.callsTo('resolvePaywallAvailability'), isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(host.callsTo('resolvePaywallAvailability'), [
        ['request', false],
      ]);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
