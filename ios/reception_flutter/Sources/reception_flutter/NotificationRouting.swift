import Foundation

/// Remembers how each notification was handled so receipts, taps and their repeats (cold start, scene and
/// notification-center deliveries of the same response, hot restarts) act once. Keeps the latest 64 keys.
@MainActor
internal final class NotificationRouting {
  enum Action { case receive, receiveAndOpen, open, ignore }
  static let capacity = 64
  private var opened: [String: Bool] = [:]
  private var order: [String] = []
  private var launchTap: (conversationId: String, drainedAt: Date)?

  /// The legacy cold-start tap is routed under a launch alias; remember it so the same response arriving later
  /// through the notification-center proxy under its own key does not open the chat again.
  func drainedLaunchTap(conversationId: String, at date: Date) {
    launchTap = (conversationId, date)
  }

  /// A tap from the notification center. A first delivery of the launch tap's conversation that was delivered
  /// before, or up to 30 s after, the launch drain is recorded as opened and ignored.
  func tapAction(for key: String, conversationId: String, deliveredAt date: Date) -> Action {
    let action = action(for: key, openChat: true)
    if action == .receiveAndOpen, let launchTap, launchTap.conversationId == conversationId,
      date <= launchTap.drainedAt.addingTimeInterval(30)
    {
      return .ignore
    }
    return action
  }

  func action(for key: String, openChat: Bool) -> Action {
    let previous = opened[key]
    if previous == true || (previous == false && !openChat) { return .ignore }
    if previous == nil {
      order.append(key)
      if order.count > Self.capacity { opened[order.removeFirst()] = nil }
    }
    opened[key] = openChat
    if openChat { return previous == nil ? .receiveAndOpen : .open }
    return .receive
  }
}
