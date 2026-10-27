import Foundation

/// Remembers how each notification was handled so receipts, taps and their repeats (cold start, scene and
/// notification-center deliveries of the same response, hot restarts) act once. Keeps the latest 64 keys.
@MainActor
internal final class NotificationRouting {
  enum Action { case receive, receiveAndOpen, open, ignore }
  static let capacity = 64
  private var opened: [String: Bool] = [:]
  private var order: [String] = []
  private let launchDate: Date
  private var launchTapConversation: String?

  init(launchDate: Date = Date()) {
    self.launchDate = launchDate
  }

  /// The legacy cold-start tap is routed under a launch alias; remember its conversation so the same response
  /// arriving later through the notification-center proxy under its own key does not open the chat again.
  func drainedLaunchTap(conversationId: String) {
    launchTapConversation = conversationId
  }

  /// A tap from the notification center. A first delivery for the launch tap's conversation of a notification
  /// delivered before this launch is that tap (or an older one): recorded as opened and ignored.
  func tapAction(for key: String, conversationId: String, deliveredAt date: Date) -> Action {
    let action = action(for: key, openChat: true)
    if action == .receiveAndOpen, launchTapConversation == conversationId, date < launchDate { return .ignore }
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
