/// Reception's native iOS support chat for Flutter apps.
///
/// Public names (every type is prefixed with `Reception` so it cannot clash
/// with other packages; keep `test/exports_test.dart` in sync):
/// Reception, ReceptionAppearance, ReceptionChatOpened, ReceptionChatView,
/// ReceptionCloseIcon, ReceptionColor, ReceptionColorScheme,
/// ReceptionDataDeleted, ReceptionError, ReceptionEvent, ReceptionFontDesign,
/// ReceptionIdentity, ReceptionIdentityRejected, ReceptionImageSent,
/// ReceptionLogLevel, ReceptionMessageSent, ReceptionPaywall,
/// ReceptionPaywallOpened, ReceptionPaywallProduct, ReceptionPushEnvironment,
/// ReceptionReviewOpened, ReceptionWelcomeIcon.
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
        ReceptionChatOpened,
        ReceptionDataDeleted,
        ReceptionEvent,
        ReceptionIdentity,
        ReceptionIdentityRejected,
        ReceptionImageSent,
        ReceptionLogLevel,
        ReceptionMessageSent,
        ReceptionPaywall,
        ReceptionPaywallOpened,
        ReceptionPaywallProduct,
        ReceptionPushEnvironment,
        ReceptionReviewOpened;
