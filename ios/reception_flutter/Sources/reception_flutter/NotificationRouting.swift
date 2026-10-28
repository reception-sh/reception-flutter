import Foundation

/// Decides how each notification receipt and tap is handled so repeats act once: cold-start, scene and
/// notification-center deliveries of the same response, and hot restarts. Remembers the latest 64 keys.
///
/// A tap that launched the app waits as the pending tap until configure drains it. While it waits, a proxy tap for
/// the same conversation is its duplicate: recorded as opened, not routed; the drain opens the chat once. A legacy
/// launch tap (key `launchKey`, no notification identifier) whose duplicate has not arrived yet arms a marker when
/// drained: within 10 s, the first proxy tap for that conversation delivered before this launch is ignored once.
@MainActor
internal final class NotificationRouting {
  enum Action { case receive, receiveAndOpen, open, ignore }
  static let capacity = 64
  /// Routing key of a tap read from legacy launch options, which carry no notification identifier.
  static let launchKey = "launch"
  private var opened: [String: Bool] = [:]
  private var order: [String] = []
  private let launchDate: Date
  private var pending: (key: String, conversationId: String, duplicateSeen: Bool)?
  private var marker: (conversationId: String, armedAt: Date)?

  init(launchDate: Date = Date()) {
    self.launchDate = launchDate
  }

  var hasPendingTap: Bool { pending != nil }

  /// Keeps a tap that arrived before configure; the latest wins.
  func queueTap(key: String, conversationId: String) {
    pending = (key, conversationId, false)
  }

  /// Opt-out: forgets the pending tap and the launch marker.
  func discardPendingTap() {
    pending = nil
    marker = nil
  }

  /// Takes the pending tap; returns the conversation to open, or nil if there was none.
  func drainPendingTap(at now: Date = Date()) -> String? {
    guard let tap = pending else { return nil }
    pending = nil
    record(tap.key, openChat: true)
    if tap.key == Self.launchKey, !tap.duplicateSeen { marker = (tap.conversationId, now) }
    return tap.conversationId
  }

  /// A default-action tap delivered by the notification center.
  func tapAction(for key: String, conversationId: String, deliveredAt date: Date, at now: Date = Date()) -> Action {
    if let tap = pending, tap.conversationId == conversationId {
      record(key, openChat: true)
      pending?.duplicateSeen = true
      return .ignore
    }
    let action = action(for: key, openChat: true)
    guard let marker else { return action }
    if now.timeIntervalSince(marker.armedAt) > 10 {
      self.marker = nil
    } else if action == .receiveAndOpen, marker.conversationId == conversationId, date < launchDate {
      self.marker = nil
      return .ignore
    }
    return action
  }

  func action(for key: String, openChat: Bool) -> Action {
    let previous = opened[key]
    if previous == true || (previous == false && !openChat) { return .ignore }
    record(key, openChat: openChat)
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
