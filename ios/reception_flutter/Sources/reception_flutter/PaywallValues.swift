/// Converts paywalls between the Pigeon messages and the SDK's values.
internal enum PaywallValues {
  static func paywall(_ message: PaywallMessage) -> ReceptionPaywall {
    ReceptionPaywall(
      id: message.id, title: message.title,
      source: message.source.map { ReceptionPaywall.Source(rawValue: $0) },
      products: message.products.map {
        ReceptionPaywall.Product(id: $0.id, price: $0.price, period: $0.period, trial: $0.trial)
      },
      presentable: message.presentable)
  }

  static func message(_ paywall: ReceptionPaywall) -> PaywallMessage {
    PaywallMessage(
      id: paywall.id, title: paywall.title, source: paywall.source?.rawValue,
      products: paywall.products.map {
        PaywallProductMessage(id: $0.id, price: $0.price, period: $0.period, trial: $0.trial)
      },
      presentable: paywall.presentable)
  }
}
