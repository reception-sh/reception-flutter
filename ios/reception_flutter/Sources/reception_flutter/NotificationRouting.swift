/// Decides how each notification receipt and tap is handled so repeats act once: cold-start, scene and
/// notification-center deliveries of the same response, and hot restarts. There is one chat per device, so every
/// tap means "open the chat", and opening it again while it is presented changes nothing.
///
/// Keys are deduplicated exactly (the latest 64 are remembered). A tap that launched the app waits as the pending
/// tap (latest wins) until the deferred drain after configure opens the chat once; every tap arriving meanwhile is
/// recorded as opened and not routed. Afterwards taps route by key again.
@MainActor
internal final class NotificationRouting {
  enum Action { case receive, receiveAndOpen, open, ignore }
  static let capacity = 64
  /// Routing key of a tap read from legacy launch options, which carry no notification identifier.
  static let launchKey = "launch"
  private var opened: [String: Bool] = [:]
  private var order: [String] = []
  private var pending: (key: String, conversationId: String)?

  var hasPendingTap: Bool { pending != nil }

  /// Keeps a tap that arrived before configure; the latest wins.
  func queueTap(key: String, conversationId: String) {
    pending = (key, conversationId)
  }

  /// Opt-out: forgets the pending tap.
  func discardPendingTap() {
    pending = nil
  }

  /// Takes the pending tap and records its key; returns the conversation to open, or nil if there was none.
  func drainPendingTap() -> String? {
    guard let tap = pending else { return nil }
    pending = nil
    record(tap.key, openChat: true)
    return tap.conversationId
  }

  func action(for key: String, openChat: Bool) -> Action {
    let previous = opened[key]
    if previous == true || (previous == false && !openChat) { return .ignore }
    record(key, openChat: openChat)
    // The pending tap's drain opens the chat; a tap before it would open it with the app's settings not yet applied.
    if openChat && pending != nil { return .ignore }
    if openChat { return previous == nil ? .receiveAndOpen : .open }
    return .receive
  }

  private func record(_ key: String, openChat: Bool) {
    if opened[key] == nil {
      order.append(key)
      if order.count > Self.capacity { opened[order.removeFirst()] = nil }
    }
    opened[key] = openChat
  }
}
