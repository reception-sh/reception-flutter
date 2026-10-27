import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reception_flutter/reception_flutter.dart';

import 'fake_host.dart';

void main() {
  testWidgets(
    'a paywall availability callback that never completes answers false after 5 s',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final host = FakeHost();
      Reception.paywallAvailability = (_) => Completer<bool>().future;
      await tester.pump();
      var answered = false;
      final reply = host
          .send('checkPaywallAvailability', ['plans', 1])
          .whenComplete(() => answered = true);
      await tester.pump(const Duration(seconds: 4));
      expect(answered, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(answered, isTrue);
      expect(await reply, isFalse);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
