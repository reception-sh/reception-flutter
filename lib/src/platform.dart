import 'package:flutter/foundation.dart';

bool _warned = false;

/// Whether Reception runs on this platform (iOS). Elsewhere logs the
/// iOS-only notice once per process and returns false.
bool checkSupported() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) return true;
  if (!_warned) {
    _warned = true;
    debugPrint('[Reception] Support chat is available on iOS only.');
  }
  return false;
}

/// Logs that an invalid [field] value was ignored, without echoing the value.
void warnInvalid(String field) =>
    debugPrint('[Reception] Invalid $field; ignored.');

/// Reports an exception thrown by an app callback without letting it reach
/// the host: Pigeon error replies with non-string details crash the Swift side.
void reportCallbackError(Object error, StackTrace stack, String context) =>
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'reception_flutter',
        context: ErrorDescription(context),
      ),
    );

/// Logs a failed fire-and-forget host call without its private diagnostics.
void bridgeFailure() => debugPrint('[Reception] Native bridge call failed.');
