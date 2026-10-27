import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'appearance.dart';
import 'messages.g.dart';
import 'platform.dart';
import 'types.dart';

/// Dart mirror of the native snapshot, plus setting assignments that native
/// has not acknowledged yet.
class ReceptionState {
  /// Whether the last native snapshot reported an accepted configuration.
  bool isConfigured = false;

  /// Unread message count.
  final unreadCount = ValueNotifier<int>(0);

  /// Whether the chat is actually visible.
  final isChatOpen = ValueNotifier<bool>(false);

  /// Registered paywalls that are currently available.
  final availablePaywalls = ValueNotifier<List<ReceptionPaywall>>(const []);

  int _revision = 0;
  Map<String, int> _settingRevisions = const {};
  Map<String, Object?> _settings = const {
    'appearance': Appearance(),
    'updatesAppBadge': true,
    'usesRemoteAppearance': true,
    'languageOverride': null,
    'logLevel': LogLevel.info,
    'paywalls': <ReceptionPaywall>[],
  };
  final _pending = <String, ({int revision, Object? value})>{};
  int _assignments = 0;

  /// The pending assignment of setting [key], else its confirmed value.
  T setting<T>(String key) =>
      (_pending.containsKey(key) ? _pending[key]!.value : _settings[key]) as T;

  /// Applies a native snapshot unless an equal or newer one was applied.
  void update(SnapshotMessage snapshot) {
    if (snapshot.revision < _revision) return;
    _revision = snapshot.revision;
    _settingRevisions = snapshot.settingRevisions;
    isConfigured = snapshot.isConfigured;
    _settings = {
      'appearance': switch (jsonDecode(snapshot.appearanceJson)) {
        final Map<String, Object?> json => appearanceFromJson(json),
        _ => const Appearance(),
      },
      'updatesAppBadge': snapshot.updatesAppBadge,
      'usesRemoteAppearance': snapshot.usesRemoteAppearance,
      'languageOverride': snapshot.languageOverride,
      'logLevel':
          LogLevel.values.asNameMap()[snapshot.logLevel] ?? LogLevel.info,
      'paywalls': List<ReceptionPaywall>.unmodifiable(
        snapshot.paywalls.map(paywallFromMessage),
      ),
    };
    _pending.removeWhere(
      (key, assignment) => (_settingRevisions[key] ?? 0) >= assignment.revision,
    );
    unreadCount.value = snapshot.unreadCount;
    isChatOpen.value = snapshot.isChatOpen;
    final available = snapshot.availablePaywalls.map(paywallFromMessage);
    if (!listEquals(available.toList(), availablePaywalls.value)) {
      availablePaywalls.value = List.unmodifiable(available);
    }
  }

  /// Keeps [value] visible for setting [key] until native acknowledges this
  /// assignment's revision or [commit] fails.
  void assign(
    String key,
    Object? value,
    Future<SnapshotMessage> Function(int revision) commit,
  ) {
    final revision = ++_assignments;
    _pending[key] = (revision: revision, value: value);
    unawaited(
      commit(revision).then(
        update,
        onError: (Object _) {
          if (_pending[key]?.revision == revision) _pending.remove(key);
          bridgeFailure();
        },
      ),
    );
  }
}
