package sh.reception.flutter

import sh.reception.ReceptionPaywall

/** Converts paywalls between the Pigeon messages and the SDK's values. */
internal object PaywallValues {
    fun paywall(message: PaywallMessage): ReceptionPaywall = ReceptionPaywall(
        id = message.id,
        title = message.title,
        source = message.source?.let { ReceptionPaywall.Source(it) },
        products = message.products.map { ReceptionPaywall.Product(it.id, it.price, it.period, it.trial) },
        presentable = message.presentable,
    )

    fun message(paywall: ReceptionPaywall): PaywallMessage = PaywallMessage(
        id = paywall.id,
        title = paywall.title,
        source = paywall.source?.rawValue,
        products = paywall.products.map { PaywallProductMessage(it.id, it.price, it.period, it.trial) },
        presentable = paywall.presentable,
    )
}
