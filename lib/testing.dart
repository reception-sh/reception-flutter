/// Debug-only helpers for verifying Reception against a local service.
library;

import 'src/reception.dart' as reception;

/// Configures Reception with [appId] against a local [serviceUrl], for example
/// `http://localhost:3000`, instead of the production service.
///
/// Works only in Debug simulator builds with a localhost [serviceUrl]; the
/// native side enforces this and leaves release builds unchanged. Like
/// `Reception.configure`, it completes immediately off iOS.
Future<void> configureReceptionForTesting({
  required String appId,
  required Uri serviceUrl,
}) => reception.configureForTesting(appId, serviceUrl.toString());
