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
  static final _api = ReceptionHostApi();
  static var _state = ReceptionState();
  static Future<void>? _connection;
  static void Function(ReceptionEvent event)? _onEvent;
  static void Function(String id)? _onPaywall;
  static List<ReceptionScreen> _screens = const [];
  static FutureOr<bool> Function(String id)? _availability;
  static var _generation = 0;

  /// The host API, connected on first use. Connecting replaces the previous
  /// Dart connection after a hot restart and hydrates state. Concurrent
  /// callers share one attempt; a failed attempt is retried by the next call.
  static Future<ReceptionHostApi> _host() async {
    final connection = _connection ??= _connect();
    try {
      await connection;
    } catch (_) {
      if (identical(_connection, connection)) _connection = null;
      rethrow;
    }
    return _api;
  }

  static Future<void> _connect() async {
    ReceptionFlutterApi.setUp(_FlutterApi());
    _state.update(await _api.connect());
  }

  static Future<T?> _call<T>(
    Future<T> Function(ReceptionHostApi host) action,
  ) async {
    if (!checkSupported()) return null;
    try {
      return await action(await _host());
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
  /// update. Use [ReceptionIdentity.user] for a real signed-in account or an entered
  /// name, or [ReceptionIdentity.token] for a signed token from your server.
  static Future<void> identify(ReceptionIdentity identity) => _call(
    (host) => switch (identity.token) {
      final token? => host.identifyToken(token),
      null => host.identify(identity.userId, identity.name, identity.email),
    },
  );

  /// Replaces the whole metadata dictionary (at most 20 fields). Names and
  /// emails belong in [identify].
  static Future<void> setMetadata(Map<String, String> metadata) {
    final snapshot = Map<String, String>.of(metadata);
    return _call((host) => host.setMetadata(snapshot));
  }

  /// Ends a real signed-in session; server history is kept. Reapply identity
  /// and metadata for the next session.
  static Future<void> logout() =>
      _call((host) async => _state.update(await host.logout()));

  /// Deletes this device's support data. Call before [logout]; throws a
  /// [ReceptionError] with code and HTTP status on failure. Without a session,
  /// after it ended, or when the App ID is unavailable, deletion can complete
  /// locally without erasing earlier server records.
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
    ReceptionPushEnvironment environment = ReceptionPushEnvironment.automatic,
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
  }) async {
    // Only this routing field is consumed natively; read it before any await.
    final id = switch (payload['reception']) {
      {'conversationId': final String id} when id.isNotEmpty => id,
      _ => null,
    };
    return await _call(
          (host) async =>
              id != null && await host.handlePushNotification(id, openChat),
        ) ??
        false;
  }

  /// Re-evaluates paywall availability; with [invalidate] after subscription
  /// changes. The result arrives asynchronously in [availablePaywalls].
  static Future<void> refreshPaywalls({bool invalidate = false}) =>
      _call((host) => host.refreshPaywalls(invalidate));

  /// Local chat styling. Assign a complete value; it is visible immediately
  /// and reconciled with native validation.
  static ReceptionAppearance get appearance {
    checkSupported();
    return _state.setting('appearance');
  }

  static set appearance(ReceptionAppearance value) {
    if (!checkSupported()) return;
    final valid = validateAppearance(
      value.toJson(),
      _state.setting<ReceptionAppearance>('appearance').toJson(),
    );
    final json = jsonEncode(valid);
    _state.assign(
      'appearance',
      appearanceFromJson(valid),
      (revision) async => (await _host()).setAppearance(json, revision),
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

  /// Whether link cards open websites inside the app (default true) instead
  /// of in the browser.
  static bool get opensWebLinksInApp {
    checkSupported();
    return _state.setting('opensWebLinksInApp');
  }

  static set opensWebLinksInApp(bool value) => _assign(
    'opensWebLinksInApp',
    value,
    (host, revision) => host.setOpensWebLinksInApp(value, revision),
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

  /// SDK log level (default [ReceptionLogLevel.info]).
  static ReceptionLogLevel get logLevel {
    checkSupported();
    return _state.setting('logLevel');
  }

  static set logLevel(ReceptionLogLevel value) => _assign(
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

  static set paywalls(List<ReceptionPaywall> value) {
    if (!checkSupported()) return;
    final paywalls = List<ReceptionPaywall>.unmodifiable(value);
    final messages = paywalls.map(paywallMessage).toList();
    _assign(
      'paywalls',
      paywalls,
      (host, revision) => host.setPaywalls(messages, revision),
    );
  }

  /// Assigns setting [key]. [commit] runs after the connection resolves, so
  /// it must only use payloads prepared before this call.
  static void _assign(
    String key,
    Object? value,
    Future<SnapshotMessage> Function(ReceptionHostApi host, int revision)
    commit,
  ) {
    if (!checkSupported()) return;
    _state.assign(
      key,
      value,
      (revision) async => commit(await _host(), revision),
    );
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
      _host()
          .then((host) => host.setPaywallHandler(value != null))
          .catchError((Object _) => bridgeFailure()),
    );
  }

  /// Places in your app that link cards can open, such as tabs, screens or
  /// the paywall. The plugin reports their IDs, so the dashboard offers them
  /// by name and sends a screen link only to app versions that list it.
  /// Invalid entries are logged and the list is ignored. A repeated ID keeps
  /// its first screen, and only the first 50 screens are kept, as the SDK
  /// reports and opens no more; extra screens are logged.
  ///
  /// A screen's callback runs after the SDK-presented chat sheet has closed,
  /// so [isChatOpen] reads false there. An embedded [ReceptionChatView] stays
  /// visible and [isChatOpen] may read true; your screen owns its dismissal.
  /// A hot restart clears the list, so assign it in `main()`.
  static List<ReceptionScreen> get screens => _screens;

  static set screens(List<ReceptionScreen> value) {
    if (!checkSupported()) return;
    if (!value.every((screen) => screen.isValid)) {
      warnInvalid('screens');
      return;
    }
    final seen = <String>{};
    final unique = value.where((screen) => seen.add(screen.id)).toList();
    if (unique.length > _maxScreens) {
      debugPrint(
        '[Reception] Only the first $_maxScreens screens are kept; '
        '${unique.length - _maxScreens} more ignored.',
      );
    }
    _screens = List.unmodifiable(unique.take(_maxScreens));
    final messages = [
      for (final screen in _screens)
        ScreenMessage(id: screen.id, value: screen.valueName),
    ];
    unawaited(
      _host()
          .then((host) => host.setScreens(messages))
          .catchError((Object _) => bridgeFailure()),
    );
  }

  /// Screens the SDK reports and opens at most.
  static const _maxScreens = 50;

  /// Decides whether a registered paywall can be offered now. Without it all
  /// registered paywalls are available. Failures, timeouts and hot restarts
  /// make pending offers unavailable. Null removes the callback.
  static FutureOr<bool> Function(String id)? get paywallAvailability =>
      _availability;

  static set paywallAvailability(FutureOr<bool> Function(String id)? value) {
    if (!checkSupported()) return;
    _availability = value;
    final generation = ++_generation;
    unawaited(
      _host()
          .then(
            (host) => host.setPaywallAvailability(value != null, generation),
          )
          .then(_state.update, onError: (Object _) => bridgeFailure()),
    );
  }
}

/// Configures against a localhost service through the same connection path as
/// [Reception.configure]; see `package:reception_flutter/testing.dart`.
Future<void> configureForTesting(String appId, String serviceUrl) =>
    Reception._call(
      (host) async => Reception._state.update(
        await host.configureForTesting(appId, serviceUrl),
      ),
    );

/// Restores the initial Dart state, as after a hot restart.
@visibleForTesting
void resetReception() {
  Reception._state = ReceptionState();
  Reception._connection = null;
  Reception._onEvent = null;
  Reception._onPaywall = null;
  Reception._screens = const [];
  Reception._availability = null;
  Reception._generation = 0;
}

class _FlutterApi implements ReceptionFlutterApi {
  @override
  void onState(SnapshotMessage state) => Reception._state.update(state);

  @override
  void onEvent(EventMessage event) {
    final handler = Reception._onEvent;
    final mapped = eventFromMessage(event);
    if (handler == null || mapped == null) return;
    try {
      handler(mapped);
    } catch (error, stack) {
      reportCallbackError(error, stack, 'while handling a Reception event');
    }
  }

  @override
  void onPaywall(String id) {
    try {
      Reception._onPaywall?.call(id);
    } catch (error, stack) {
      reportCallbackError(error, stack, 'while opening paywall "$id"');
    }
  }

  @override
  void onScreen(String id, String? value) {
    // The first screen of an ID wins, as in the Swift SDK.
    final screen = Reception._screens
        .where((item) => item.id == id)
        .firstOrNull;
    if (screen == null) return;
    try {
      if (screen.onOpenWithValue case final open?) {
        if (value != null) open(value);
      } else {
        screen.onOpen?.call();
      }
    } catch (error, stack) {
      reportCallbackError(error, stack, 'while opening screen "$id"');
    }
  }

  @override
  void requestPaywallAvailability(
    String requestId,
    String id,
    int generation,
  ) => unawaited(_resolveAvailability(requestId, id, generation));

  /// Always resolves the request: native keeps it pending until Dart answers.
  Future<void> _resolveAvailability(
    String requestId,
    String id,
    int generation,
  ) async {
    final handler = Reception._availability;
    var allowed = false;
    try {
      if (handler != null && generation == Reception._generation) {
        allowed = await Future.value(
          handler(id),
        ).timeout(const Duration(seconds: 5), onTimeout: () => false);
      }
    } catch (error, stack) {
      reportCallbackError(
        error,
        stack,
        'while checking paywall availability; offer unavailable',
      );
    }
    allowed =
        allowed &&
        handler == Reception._availability &&
        generation == Reception._generation;
    try {
      await (await Reception._host()).resolvePaywallAvailability(
        requestId,
        allowed,
      );
    } catch (_) {
      bridgeFailure();
    }
  }
}
