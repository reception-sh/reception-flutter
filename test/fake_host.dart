import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reception_flutter/src/messages.g.dart';

const _prefix = 'dev.flutter.pigeon.reception_flutter';
const _codec = ReceptionHostApi.pigeonChannelCodec;

const _methods = [
  'version',
  'connect',
  'configure',
  'configureForTesting',
  'identify',
  'identifyToken',
  'setMetadata',
  'logout',
  'deleteData',
  'openChat',
  'closeChat',
  'track',
  'setPushToken',
  'registerForPushIfAuthorized',
  'handlePushNotification',
  'setAppearance',
  'setUpdatesAppBadge',
  'setUsesRemoteAppearance',
  'setLanguageOverride',
  'setLogLevel',
  'setPaywalls',
  'setPaywallHandler',
  'setPaywallAvailability',
  'resolvePaywallAvailability',
  'refreshPaywalls',
];

/// A native snapshot with defaults matching a fresh host.
SnapshotMessage snapshot({
  int revision = 1,
  Map<String, int> settingRevisions = const {},
  bool isConfigured = false,
  int unreadCount = 0,
  bool isChatOpen = false,
  List<PaywallMessage> availablePaywalls = const [],
  List<PaywallMessage> paywalls = const [],
  String appearanceJson = '{}',
  bool updatesAppBadge = true,
  bool usesRemoteAppearance = true,
  String? languageOverride,
  String logLevel = 'info',
}) => SnapshotMessage(
  revision: revision,
  settingRevisions: settingRevisions,
  isConfigured: isConfigured,
  unreadCount: unreadCount,
  isChatOpen: isChatOpen,
  availablePaywalls: availablePaywalls,
  paywalls: paywalls,
  appearanceJson: appearanceJson,
  updatesAppBadge: updatesAppBadge,
  usesRemoteAppearance: usesRemoteAppearance,
  languageOverride: languageOverride,
  logLevel: logLevel,
);

/// Mocks the iOS host on the Pigeon channels of the test binary messenger.
class FakeHost {
  FakeHost() {
    for (final method in _methods) {
      _messenger.setMockMessageHandler('$_prefix.ReceptionHostApi.$method', (
        data,
      ) async {
        final args = (_codec.decodeMessage(data) as List<Object?>?) ?? [];
        calls.add((method, args));
        try {
          return _codec.encodeMessage(<Object?>[await handlers[method]!(args)]);
        } on PlatformException catch (error) {
          return _codec.encodeMessage(<Object?>[
            error.code,
            error.message,
            error.details,
          ]);
        }
      });
    }
  }

  final _messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Every host call in order: method name and arguments.
  final calls = <(String, List<Object?>)>[];

  /// Replies by method; replace an entry to script a test.
  final Map<String, FutureOr<Object?> Function(List<Object?> args)> handlers = {
    for (final method in _methods) method: (_) => null,
    'version': (_) => '1.6.0',
    'connect': (_) => snapshot(),
    'configure': (_) => snapshot(revision: 2, isConfigured: true),
    'configureForTesting': (_) => snapshot(),
    'logout': (_) => snapshot(revision: 3),
    'deleteData': (_) => DeleteResultMessage(state: snapshot()),
    'handlePushNotification': (_) => true,
    'setAppearance': (args) => snapshot(appearanceJson: args[0]! as String),
    'setUpdatesAppBadge': (args) => snapshot(updatesAppBadge: args[0]! as bool),
    'setUsesRemoteAppearance': (args) =>
        snapshot(usesRemoteAppearance: args[0]! as bool),
    'setLanguageOverride': (args) =>
        snapshot(languageOverride: args[0] as String?),
    'setLogLevel': (args) => snapshot(logLevel: args[0]! as String),
    'setPaywalls': (args) =>
        snapshot(paywalls: (args[0]! as List<Object?>).cast()),
    'setPaywallAvailability': (_) => snapshot(),
  };

  /// Arguments of every call to [method].
  List<List<Object?>> callsTo(String method) => [
    for (final (name, args) in calls)
      if (name == method) args,
  ];

  /// Sends a host → Dart call through the messenger and returns its result.
  Future<Object?> send(String method, List<Object?> args) async {
    final reply = Completer<ByteData?>();
    await _messenger.handlePlatformMessage(
      '$_prefix.ReceptionFlutterApi.$method',
      _codec.encodeMessage(args),
      reply.complete,
    );
    final result = _codec.decodeMessage(await reply.future) as List<Object?>;
    if (result.length > 1) throw StateError('Dart replied with ${result[0]}');
    return result.firstOrNull;
  }
}

/// Captures `debugPrint` output for the current test.
List<String> captureLogs() {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
  addTearDown(() => debugPrint = original);
  return logs;
}

/// Captures errors reported through `FlutterError.reportError`.
List<FlutterErrorDetails> captureErrors() {
  final errors = <FlutterErrorDetails>[];
  final original = FlutterError.onError;
  FlutterError.onError = errors.add;
  addTearDown(() => FlutterError.onError = original);
  return errors;
}
