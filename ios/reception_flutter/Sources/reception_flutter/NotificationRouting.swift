/// Remembers how each notification was handled so receipts, taps and their repeats (cold start, scene and
/// notification-center deliveries of the same response, hot restarts) act once. Keeps the latest 64 keys.
@MainActor
internal final class NotificationRouting {
  enum Action { case receive, receiveAndOpen, open, ignore }
  static let capacity = 64
  private var opened: [String: Bool] = [:]
  private var order: [String] = []

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
