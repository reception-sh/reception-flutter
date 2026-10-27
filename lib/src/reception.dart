import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'appearance.dart';
import 'errors.dart';
import 'messages.g.dart';
import 'platform.dart';
import 'sdk_version.dart';
import 'state.dart';
import 'types.dart';

/// Reception's native iOS support chat. On other platforms every call
/// completes immediately, state keeps its defaults, and a notice is logged
/// once.
abstract final class Reception {
  static final _host = ReceptionHostApi();
  static var _state = ReceptionState();
  static var _connected = false;
  static void Function(ReceptionEvent event)? _onEvent;
  static void Function(String id)? _onPaywall;
  static FutureOr<bool> Function(String id)? _availability;
  static var _generation = 0;

  /// The host API, connected on first use. Connecting replaces the previous
  /// Dart connection after a hot restart and hydrates state.
  static ReceptionHostApi get _api {
    if (!_connected) {
      _connected = true;
      ReceptionFlutterApi.setUp(_FlutterApi());
      unawaited(
        _host.connect().then(
          _state.update,
          onError: (Object _) => bridgeFailure(),
        ),
      );
    }
    return _host;
  }

  static Future<T?> _call<T>(
    Future<T> Function(ReceptionHostApi host) action,
  ) async {
    if (!checkSupported()) return null;
    try {
      return await action(_api);
    } catch (error) {
      throw ReceptionError.from(error);
    }
  }

  /// Configures Reception with your public App ID from the dashboard
  /// (Settings → your app → General). Call once at startup before identity or
  /// chat. With [handlesNotifications] (default), the plugin routes Reception
  /// notifications natively and forwards all others to the existing
  /// notification delegate.
  static Future<void> configure({
    required String appId,
    bool handlesNotifications = true,
  }) => _call(
    (host) async =>
        _state.update(await host.configure(appId, handlesNotifications)),
  );

  /// Whether native accepted the configuration (not whether it is online).
  static bool get isConfigured {
    checkSupported();
    return _state.isConfigured;
  }

  /// Version of the bundled iOS SDK.
  static String get version {
    checkSupported();
    return sdkVersion;
  }

  /// Live unread message count; 0 off iOS.
  static ValueListenable<int> get unreadCount {
    checkSupported();
    return _state.unreadCount;
  }

  /// Whether the chat is actually visible, not just requested; false off iOS.
  static ValueListenable<bool> get isChatOpen {
    checkSupported();
    return _state.isChatOpen;
  }

  /// Registered [paywalls] that are currently available, filtered by
  /// [paywallAvailability].
  static ValueListenable<List<ReceptionPaywall>> get availablePaywalls {
    checkSupported();
    return _state.availablePaywalls;
  }

  /// Presents the chat sheet.
  static Future<void> openChat() => _call((host) => host.openChat());

  /// Dismisses the chat sheet (not an embedded [ReceptionChatView]).
  static Future<void> closeChat() => _call((host) => host.closeChat());

  /// Identifies the person on this device; staged for the next device
  /// update. Use [Identity.user] for a real signed-in account or an entered
  /// name, or [Identity.token] for a signed token from your server.
  static Future<void> identify(Identity identity) => _call(
    (host) => switch (identity.token) {
      final token? => host.identifyToken(token),
      null => host.identify(identity.userId, identity.name, identity.email),
    },
  );

  /// Replaces the whole metadata dictionary (at most 20 fields). Names and
  /// emails belong in [identify].
  static Future<void> setMetadata(Map<String, String> metadata) =>
      _call((host) => host.setMetadata(metadata));

  /// Ends a real signed-in session; server history is kept. Reapply identity
  /// and metadata for the next session.
  static Future<void> logout() =>
      _call((host) async => _state.update(await host.logout()));

  /// Deletes this device's support data. Call before [logout]; throws a
  /// [ReceptionError] with code and HTTP status on failure.
  static Future<void> deleteData() => _call((host) async {
    final result = await host.deleteData();
    _state.update(result.state);
    if (result.error case final error?) throw ReceptionError.from(error);
  });

  /// Reports an app [event], for example `paywall_declined`, to dashboard
  /// automations. A listening automation sends its message and can open the
  /// chat; with [opensChat] it also reopens at later events. Offline or
  /// without a listening automation nothing happens.
  static Future<void> track(String event, {bool opensChat = false}) =>
      _call((host) => host.track(event, opensChat));

  /// Registers a raw APNs device token in hex (never an FCM token). Invalid
  /// tokens are logged and ignored.
  static Future<void> setPushToken(
    String hexToken, {
    PushEnvironment environment = PushEnvironment.automatic,
  }) => _call((host) async {
    if (hexToken.length > 512 || !_pushToken.hasMatch(hexToken)) {
      warnInvalid('APNs token or environment');
      return;
    }
    await host.setPushToken(hexToken.toLowerCase(), environment.name);
  });

  static final _pushToken = RegExp(r'^(?:[\da-f]{2})+$', caseSensitive: false);

  /// Requests the APNs token again when notifications are already
  /// authorized. Never prompts.
  static Future<void> registerForPushIfAuthorized() =>
      _call((host) => host.registerForPushIfAuthorized());

  /// Routes a raw APNs [payload] you received yourself. Returns true for a
  /// Reception notification and false for others. Pass [openChat] false for
  /// foreground receipt and true (default) for taps.
  static Future<bool> handlePushNotification(
    Map<String, Object?> payload, {
    bool openChat = true,
  }) async =>
      await _call((host) async {
        // Only this routing field is consumed natively.
        if (payload['reception'] case {
          'conversationId': final String id,
        } when id.isNotEmpty) {
          return host.handlePushNotification(id, openChat);
        }
        return false;
      }) ??
      false;

  /// Re-evaluates paywall availability; with [invalidate] after subscription
  /// changes. The result arrives asynchronously in [availablePaywalls].
  static Future<void> refreshPaywalls({bool invalidate = false}) =>
      _call((host) => host.refreshPaywalls(invalidate));

  /// Local chat styling. Assign a complete value; it is visible immediately
  /// and reconciled with native validation.
  static Appearance get appearance {
    checkSupported();
    return _state.setting('appearance');
  }

  static set appearance(Appearance value) {
    if (!checkSupported()) return;
    final valid = validateAppearance(
      value.toJson(),
      _state.setting<Appearance>('appearance').toJson(),
    );
    final host = _api;
    _state.assign(
      'appearance',
      appearanceFromJson(valid),
      (revision) => host.setAppearance(jsonEncode(valid), revision),
    );
  }

  /// Whether Reception updates the app icon badge (default true). Set false
  /// if your app owns the badge and notification cleanup.
  static bool get updatesAppBadge {
    checkSupported();
    return _state.setting('updatesAppBadge');
  }

  static set updatesAppBadge(bool value) => _assign(
    'updatesAppBadge',
    value,
    (host, revision) => host.setUpdatesAppBadge(value, revision),
  );

  /// Whether published dashboard appearance overrides local [appearance]
  /// (default true).
  static bool get usesRemoteAppearance {
    checkSupported();
    return _state.setting('usesRemoteAppearance');
  }

  static set usesRemoteAppearance(bool value) => _assign(
    'usesRemoteAppearance',
    value,
    (host, revision) => host.setUsesRemoteAppearance(value, revision),
  );

  /// BCP 47 language tag for an in-app language picker; null (default)
  /// follows the app's iOS localization.
  static String? get languageOverride {
    checkSupported();
    return _state.setting('languageOverride');
  }

  static set languageOverride(String? value) => _assign(
    'languageOverride',
    value,
    (host, revision) => host.setLanguageOverride(value, revision),
  );

  /// SDK log level (default [LogLevel.info]).
  static LogLevel get logLevel {
    checkSupported();
    return _state.setting('logLevel');
  }

  static set logLevel(LogLevel value) => _assign(
    'logLevel',
    value,
    (host, revision) => host.setLogLevel(value.name, revision),
  );

  /// Purchase screens your app owns that chat replies can offer. A card needs
  /// both an available ID and [onPaywall].
  static List<ReceptionPaywall> get paywalls {
    checkSupported();
    return _state.setting('paywalls');
  }

  static set paywalls(List<ReceptionPaywall> value) => _assign(
    'paywalls',
    List<ReceptionPaywall>.unmodifiable(value),
    (host, revision) =>
        host.setPaywalls(value.map(paywallMessage).toList(), revision),
  );

  static void _assign(
    String key,
    Object? value,
    Future<SnapshotMessage> Function(ReceptionHostApi host, int revision)
    commit,
  ) {
    if (!checkSupported()) return;
    final host = _api;
    _state.assign(key, value, (revision) => commit(host, revision));
  }

  /// Receives chat events. Assignment replaces the previous handler; null
  /// removes it.
  static void Function(ReceptionEvent event)? get onEvent => _onEvent;

  static set onEvent(void Function(ReceptionEvent event)? value) {
    if (checkSupported()) _onEvent = value;
  }

  /// Presents your paywall with [ReceptionPaywall.id] above the chat, which
  /// stays open. Null removes the handler.
  static void Function(String id)? get onPaywall => _onPaywall;

  static set onPaywall(void Function(String id)? value) {
    if (!checkSupported()) return;
    _onPaywall = value;
    unawaited(
      _api
          .setPaywallHandler(value != null)
          .catchError((Object _) => bridgeFailure()),
    );
  }

  /// Decides whether a registered paywall can be offered now. Without it all
  /// registered paywalls are available. Failures, timeouts and hot restarts
  /// make pending offers unavailable. Null removes the callback.
  static FutureOr<bool> Function(String id)? get paywallAvailability =>
      _availability;

  static set paywallAvailability(FutureOr<bool> Function(String id)? value) {
    if (!checkSupported()) return;
    _availability = value;
    _generation += 1;
    unawaited(
      _api
          .setPaywallAvailability(value != null, _generation)
          .then(_state.update, onError: (Object _) => bridgeFailure()),
    );
  }
}

/// Restores the initial Dart state, as after a hot restart.
@visibleForTesting
void resetReception() {
  Reception._state = ReceptionState();
  Reception._connected = false;
  Reception._onEvent = null;
  Reception._onPaywall = null;
  Reception._availability = null;
  Reception._generation = 0;
}

class _FlutterApi implements ReceptionFlutterApi {
  @override
  void onState(SnapshotMessage state) => Reception._state.update(state);

  @override
  void onEvent(EventMessage event) {
    if (eventFromMessage(event) case final mapped?) {
      Reception._onEvent?.call(mapped);
    }
  }

  @override
  void onPaywall(String id) => Reception._onPaywall?.call(id);

  @override
  Future<bool> checkPaywallAvailability(String id, int generation) async {
    final handler = Reception._availability;
    var allowed = false;
    try {
      if (handler != null && generation == Reception._generation) {
        allowed = await handler(id);
      }
    } catch (_) {
      debugPrint(
        '[Reception] Paywall availability callback failed; offer unavailable.',
      );
    }
    return allowed &&
        handler == Reception._availability &&
        generation == Reception._generation;
  }
}
