// Bridge contract between Dart and the iOS host. Regenerate with:
//   dart run pigeon --input pigeons/reception.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    swiftOut:
        'ios/reception_flutter/Sources/reception_flutter/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'ReceptionBridgeError'),
    dartPackageName: 'reception_flutter',
  ),
)
/// A product a paywall sells. Mirrors the public Dart type one to one.
class PaywallMessage {
  PaywallMessage({
    required this.id,
    required this.title,
    this.source,
    required this.products,
    required this.presentable,
  });
  String id;
  String title;
  String? source;
  List<PaywallProductMessage> products;
  bool presentable;
}

class PaywallProductMessage {
  PaywallProductMessage({
    required this.id,
    this.price,
    this.period,
    this.trial,
  });
  String id;
  String? price;
  String? period;
  String? trial;
}

/// Native state, published after every change and returned by state-changing calls.
class SnapshotMessage {
  SnapshotMessage({
    required this.revision,
    required this.settingRevisions,
    required this.isConfigured,
    required this.unreadCount,
    required this.isChatOpen,
    required this.availablePaywalls,
    required this.paywalls,
    required this.appearanceJson,
    required this.updatesAppBadge,
    required this.usesRemoteAppearance,
    this.languageOverride,
    required this.logLevel,
  });
  int revision;
  Map<String, int> settingRevisions;
  bool isConfigured;
  int unreadCount;
  bool isChatOpen;
  List<PaywallMessage> availablePaywalls;
  List<PaywallMessage> paywalls;
  String appearanceJson;
  bool updatesAppBadge;
  bool usesRemoteAppearance;
  String? languageOverride;
  String logLevel;
}

class ErrorMessage {
  ErrorMessage({required this.code, required this.status});
  String code;
  int status;
}

class DeleteResultMessage {
  DeleteResultMessage({required this.state, this.error});
  SnapshotMessage state;
  ErrorMessage? error;
}

class EventMessage {
  EventMessage({required this.type, this.error});
  String type;
  ErrorMessage? error;
}

/// Calls from Dart to the iOS host. Every method runs on the main thread.
@HostApi()
abstract class ReceptionHostApi {
  String version();

  /// Replaces any previous Dart connection (hot restart) and returns the current state.
  SnapshotMessage connect();

  SnapshotMessage configure(String appId, bool handlesNotifications);

  /// Debug simulator builds only: configure against a localhost service. No-op in release builds.
  SnapshotMessage configureForTesting(String appId, String serviceUrl);

  void identify(String? userId, String? name, String? email);
  void identifyToken(String token);
  void setMetadata(Map<String, String> metadata);
  SnapshotMessage logout();
  @asyncCallback
  DeleteResultMessage deleteData();

  void openChat();
  void closeChat();
  void track(String event, bool opensChat);

  void setPushToken(String hexToken, String environment);
  @asyncCallback
  void registerForPushIfAuthorized();
  bool handlePushNotification(String conversationId, bool openChat);

  SnapshotMessage setAppearance(String json, int revision);
  SnapshotMessage setUpdatesAppBadge(bool value, int revision);
  SnapshotMessage setUsesRemoteAppearance(bool value, int revision);
  SnapshotMessage setLanguageOverride(String? value, int revision);
  SnapshotMessage setLogLevel(String value, int revision);
  SnapshotMessage setPaywalls(List<PaywallMessage> value, int revision);

  void setPaywallHandler(bool enabled);
  SnapshotMessage setPaywallAvailability(bool enabled, int generation);
  void refreshPaywalls(bool invalidate);
}

/// Calls from the iOS host to Dart.
@FlutterApi()
abstract class ReceptionFlutterApi {
  void onState(SnapshotMessage state);
  void onEvent(EventMessage event);
  void onPaywall(String id);

  /// Asked for each registered paywall; the host fails closed after five seconds or on a stale generation.
  @async
  bool checkPaywallAvailability(String id, int generation);
}
