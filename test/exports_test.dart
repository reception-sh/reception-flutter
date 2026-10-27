// Compiles only if the public library exports each intended name; the
// `show`-only import below fails to compile when one is missing or renamed.
// Keep in sync with the list in lib/reception_flutter.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:reception_flutter/reception_flutter.dart'
    show
        Reception,
        ReceptionAppearance,
        ReceptionChatOpened,
        ReceptionChatView,
        ReceptionCloseIcon,
        ReceptionColor,
        ReceptionColorScheme,
        ReceptionDataDeleted,
        ReceptionError,
        ReceptionEvent,
        ReceptionFontDesign,
        ReceptionIdentity,
        ReceptionIdentityRejected,
        ReceptionImageSent,
        ReceptionLogLevel,
        ReceptionMessageSent,
        ReceptionPaywall,
        ReceptionPaywallOpened,
        ReceptionPaywallProduct,
        ReceptionPushEnvironment,
        ReceptionReviewOpened,
        ReceptionWelcomeIcon;
import 'package:reception_flutter/reception_flutter.dart' as public;

void main() {
  test('the public library exports exactly the Reception-prefixed names', () {
    const exported = <Type>[
      Reception,
      ReceptionAppearance,
      ReceptionChatOpened,
      ReceptionChatView,
      ReceptionCloseIcon,
      ReceptionColor,
      ReceptionColorScheme,
      ReceptionDataDeleted,
      ReceptionError,
      ReceptionEvent,
      ReceptionFontDesign,
      ReceptionIdentity,
      ReceptionIdentityRejected,
      ReceptionImageSent,
      ReceptionLogLevel,
      ReceptionMessageSent,
      ReceptionPaywall,
      ReceptionPaywallOpened,
      ReceptionPaywallProduct,
      ReceptionPushEnvironment,
      ReceptionReviewOpened,
      ReceptionWelcomeIcon,
    ];
    expect(exported.toSet(), hasLength(22));
    expect(
      exported.map((type) => '$type'),
      everyElement(startsWith('Reception')),
    );
  });

  test('event cases are the sealed ReceptionEvent subtypes', () {
    const events = <public.ReceptionEvent>[
      public.ReceptionChatOpened(),
      public.ReceptionMessageSent(),
      public.ReceptionImageSent(),
      public.ReceptionReviewOpened(),
      public.ReceptionPaywallOpened(),
      public.ReceptionDataDeleted(),
      public.ReceptionIdentityRejected(public.ReceptionError('code', 0)),
    ];
    expect(events, hasLength(7));
  });
}
