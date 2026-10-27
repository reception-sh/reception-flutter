import 'package:flutter/foundation.dart';

import 'messages.g.dart';

/// A failure reported by Reception, with a stable [code] and the HTTP
/// [status] (0 when no HTTP response was involved).
@immutable
class ReceptionError implements Exception {
  /// Creates an error with [code] and [status].
  const ReceptionError(this.code, this.status);

  /// Converts [error] to a [ReceptionError]. Anything that is not already a
  /// Reception error becomes `bridge_error` with status 0, so private native
  /// diagnostics never reach the app.
  factory ReceptionError.from(Object error) => switch (error) {
    ReceptionError() => error,
    ErrorMessage(:final code, :final status) => ReceptionError(code, status),
    _ => const ReceptionError('bridge_error', 0),
  };

  /// Stable error code, for example `identity_token_expired` or `bridge_error`.
  final String code;

  /// HTTP status of the failed request, or 0.
  final int status;

  @override
  bool operator ==(Object other) =>
      other is ReceptionError && other.code == code && other.status == status;

  @override
  int get hashCode => Object.hash(code, status);

  @override
  String toString() => 'ReceptionError: $code ($status)';
}
