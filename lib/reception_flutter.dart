/// Reception's native support chat for Flutter apps on iOS and Android.
///
/// Public names (every type is prefixed with `Reception` so it cannot clash
/// with other packages; keep `test/exports_test.dart` in sync):
/// Reception, ReceptionAndroidOptions, ReceptionAppearance,
/// ReceptionChatOpened, ReceptionChatView, ReceptionCloseIcon,
/// ReceptionColor, ReceptionColorScheme,
/// ReceptionDataDeleted, ReceptionError, ReceptionEvent, ReceptionFontDesign,
/// ReceptionIdentity, ReceptionIdentityRejected, ReceptionImageSent,
/// ReceptionLinkOpened, ReceptionLogLevel, ReceptionMessageSent,
/// ReceptionPaywall, ReceptionPaywallOpened, ReceptionPaywallProduct,
/// ReceptionPushEnvironment, ReceptionReviewOpened, ReceptionScreen,
/// ReceptionWelcomeIcon.
library;

export 'src/appearance.dart'
    show
        ReceptionAppearance,
        ReceptionCloseIcon,
        ReceptionColor,
        ReceptionColorScheme,
        ReceptionFontDesign,
        ReceptionWelcomeIcon;
export 'src/chat_view.dart' show ReceptionChatView;
export 'src/errors.dart' show ReceptionError;
export 'src/reception.dart' show Reception;
export 'src/types.dart'
    show
        ReceptionAndroidOptions,
        ReceptionChatOpened,
        ReceptionDataDeleted,
        ReceptionEvent,
        ReceptionIdentity,
        ReceptionIdentityRejected,
        ReceptionImageSent,
        ReceptionLinkOpened,
        ReceptionLogLevel,
        ReceptionMessageSent,
        ReceptionPaywall,
        ReceptionPaywallOpened,
        ReceptionPaywallProduct,
        ReceptionPushEnvironment,
        ReceptionReviewOpened,
        ReceptionScreen;
