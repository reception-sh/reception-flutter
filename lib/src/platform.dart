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

/// Logs a failed fire-and-forget host call without its private diagnostics.
void bridgeFailure() => debugPrint('[Reception] Native bridge call failed.');
