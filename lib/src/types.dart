import 'package:flutter/foundation.dart';

import 'errors.dart';
import 'messages.g.dart';

/// A product a paywall sells, shown to your team in the dashboard.
@immutable
class ReceptionPaywallProduct {
  /// Creates a product entry.
  const ReceptionPaywallProduct({
    required this.id,
    this.price,
    this.period,
    this.trial,
  });

  /// Store product identifier.
  final String id;

  /// Localized price, for example `$59.99`.
  final String? price;

  /// Billing period as an ISO 8601 duration, for example `P1M`.
  final String? period;

  /// Trial length as an ISO 8601 duration, for example `P1W`.
  final String? trial;

  @override
  bool operator ==(Object other) =>
      other is ReceptionPaywallProduct &&
      other.id == id &&
      other.price == price &&
      other.period == period &&
      other.trial == trial;

  @override
  int get hashCode => Object.hash(id, price, period, trial);
}

/// A purchase screen your app owns, registered so support replies can offer it.
@immutable
class ReceptionPaywall {
  /// Creates a paywall entry.
  const ReceptionPaywall({
    required this.id,
    required this.title,
    this.source,
    this.products = const [],
    this.presentable = true,
  });

  /// Stable identifier passed to `Reception.onPaywall`.
  final String id;

  /// Name shown to your team in the dashboard, not to customers.
  final String title;

  /// Where the paywall is built: `revenuecat`, `superwall`, `adapty`, `app`
  /// or another lowercase vendor name.
  final String? source;

  /// Products the paywall sells.
  final List<ReceptionPaywallProduct> products;

  /// False lists an offering without a paywall for your team; a card never
  /// opens it.
  final bool presentable;

  @override
  bool operator ==(Object other) =>
      other is ReceptionPaywall &&
      other.id == id &&
      other.title == title &&
      other.source == source &&
      listEquals(other.products, products) &&
      other.presentable == presentable;

  @override
  int get hashCode =>
      Object.hash(id, title, source, Object.hashAll(products), presentable);
}

/// A copy of [paywall] whose products cannot change after assignment.
ReceptionPaywall frozenPaywall(ReceptionPaywall paywall) => ReceptionPaywall(
  id: paywall.id,
  title: paywall.title,
  source: paywall.source,
  products: List.unmodifiable(paywall.products),
  presentable: paywall.presentable,
);

/// Converts [paywall] to its bridge message.
PaywallMessage paywallMessage(ReceptionPaywall paywall) => PaywallMessage(
  id: paywall.id,
  title: paywall.title,
  source: paywall.source,
  products: [
    for (final product in paywall.products)
      PaywallProductMessage(
        id: product.id,
        price: product.price,
        period: product.period,
        trial: product.trial,
      ),
  ],
  presentable: paywall.presentable,
);

/// Converts a bridge [message] to a [ReceptionPaywall].
ReceptionPaywall paywallFromMessage(PaywallMessage message) => ReceptionPaywall(
  id: message.id,
  title: message.title,
  source: message.source,
  products: List.unmodifiable([
    for (final product in message.products)
      ReceptionPaywallProduct(
        id: product.id,
        price: product.price,
        period: product.period,
        trial: product.trial,
      ),
  ]),
  presentable: message.presentable,
);

/// APNs environment of a push token.
enum ReceptionPushEnvironment {
  /// Detected from the app's signing (default).
  automatic,

  /// Development APNs.
  sandbox,

  /// Production APNs.
  production,
}

/// Amount of SDK logging.
enum ReceptionLogLevel {
  /// No logging.
  off,

  /// Errors only.
  error,

  /// Errors and important events (default).
  info,

  /// Everything, for troubleshooting.
  debug,
}

/// Who the current person is: a self-reported user or a verified token.
@immutable
class ReceptionIdentity {
  /// Labels this device with a real signed-in account ID (null when there is
  /// none) and optional name and email. It does not authenticate anyone.
  const ReceptionIdentity.user({this.userId, this.name, this.email})
    : token = null;

  /// A verified identity: a signed token fetched from your own server.
  const ReceptionIdentity.token(String this.token)
    : userId = null,
      name = null,
      email = null;

  /// Your account ID, or null for a person without a signed-in account.
  final String? userId;

  /// Display name.
  final String? name;

  /// Email address.
  final String? email;

  /// Signed identity token, set only by [ReceptionIdentity.token].
  final String? token;
}

/// Something that happened in the chat, delivered to `Reception.onEvent`.
sealed class ReceptionEvent {
  const ReceptionEvent();
}

/// The chat became visible.
final class ReceptionChatOpened extends ReceptionEvent {
  /// Creates the event.
  const ReceptionChatOpened();
}

/// The person sent a message.
final class ReceptionMessageSent extends ReceptionEvent {
  /// Creates the event.
  const ReceptionMessageSent();
}

/// The person sent an image.
final class ReceptionImageSent extends ReceptionEvent {
  /// Creates the event.
  const ReceptionImageSent();
}

/// The person opened an App Store review prompt from the chat.
final class ReceptionReviewOpened extends ReceptionEvent {
  /// Creates the event.
  const ReceptionReviewOpened();
}

/// The person opened a paywall card from the chat.
final class ReceptionPaywallOpened extends ReceptionEvent {
  /// Creates the event.
  const ReceptionPaywallOpened();
}

/// This device's support data was deleted.
final class ReceptionDataDeleted extends ReceptionEvent {
  /// Creates the event.
  const ReceptionDataDeleted();
}

/// The server rejected the identity token. Refresh the token only when
/// [error] has code `identity_token_expired`; other codes need a server fix.
final class ReceptionIdentityRejected extends ReceptionEvent {
  /// Creates the event with its [error].
  const ReceptionIdentityRejected(this.error);

  /// Why the identity was rejected.
  final ReceptionError error;
}

/// Maps a bridge [message] to a [ReceptionEvent]; null for unknown events.
ReceptionEvent? eventFromMessage(EventMessage message) =>
    switch ((message.type, message.error)) {
      ('chatOpened', _) => const ReceptionChatOpened(),
      ('messageSent', _) => const ReceptionMessageSent(),
      ('imageSent', _) => const ReceptionImageSent(),
      ('reviewOpened', _) => const ReceptionReviewOpened(),
      ('paywallOpened', _) => const ReceptionPaywallOpened(),
      ('dataDeleted', _) => const ReceptionDataDeleted(),
      ('identityRejected', final ErrorMessage error) =>
        ReceptionIdentityRejected(ReceptionError.from(error)),
      _ => null,
    };
