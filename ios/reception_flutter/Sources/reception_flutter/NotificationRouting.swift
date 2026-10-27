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
  private var launchTap: (conversationId: String, drainedAt: Date)?

  init(launchDate: Date = Date()) {
    self.launchDate = launchDate
  }

  /// The legacy cold-start tap is routed under a launch alias. iOS may deliver the same response moments later
  /// through the notification-center proxy under its own key; remember the tap so that delivery is ignored.
  func drainedLaunchTap(conversationId: String, at date: Date = Date()) {
    launchTap = (conversationId, date)
  }

  /// A tap from the notification center. Within 10 s of the launch drain, the first tap for the launch tap's
  /// conversation whose notification was delivered before this launch is that duplicate: recorded as opened and
  /// ignored, once. Afterwards every tap routes.
  func tapAction(for key: String, conversationId: String, deliveredAt date: Date, at now: Date = Date()) -> Action {
    let action = action(for: key, openChat: true)
    guard let launchTap else { return action }
    if now.timeIntervalSince(launchTap.drainedAt) > 10 {
      self.launchTap = nil
    } else if action == .receiveAndOpen, launchTap.conversationId == conversationId, date < launchDate {
      self.launchTap = nil
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
