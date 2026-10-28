import UIKit
import UserNotifications
import os

/// Process-wide push support: caches the APNs token across configure, logout and deletion, captures notification
/// taps that launched the app, and owns the notification-center proxy. Survives hot restarts with the plugin.
@MainActor
internal final class ReceptionNotifications {
  static let shared = ReceptionNotifications()
  static let logger = Logger(subsystem: "com.reception.flutter", category: "Notifications")
  private var token: (data: Data, environment: Reception.PushEnvironment)?
  /// Nil until the first successful configure decides whether the plugin handles notifications.
  private var handlesNotifications: Bool?
  private var drain: Task<Void, Never>?
  private let routing = NotificationRouting()
  private var proxy: ReceptionNotificationCenter?
  private var reportedReplacement = false

  func setToken(_ data: Data, environment: Reception.PushEnvironment) {
    token = (data, environment)
    applyToken()
  }

  /// Called after every configure from Dart.
  func configured(handlesNotifications handles: Bool) {
    guard Reception.isConfigured else { return }
    handlesNotifications = handles
    restorePush()
    if handles {
      installProxy()
      scheduleDrain()
    } else {
      drain?.cancel()
      routing.discardPendingTap()
      removeProxy()
    }
  }

  /// Opens the chat for the pending tap shortly after configure, so the settings Dart applies right after
  /// `configure` returns (appearance, language) are in place first. A later configure reschedules it.
  private func scheduleDrain() {
    drain?.cancel()
    guard routing.hasPendingTap else { return }
    drain = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
      // A reconfigure may have cancelled this task while the sleep was already over.
      guard !Task.isCancelled, let self, self.handlesNotifications == true,
        let id = self.routing.drainPendingTap()
      else { return }
      self.perform(.receiveAndOpen, conversationId: id, openChat: true)
    }
  }

  /// Hands the cached token to the SDK again (configure, logout and deletion clear its staged token) and asks APNs
  /// for a fresh one when permission already exists.
  func restorePush() {
    applyToken()
    registerIfAuthorized()
  }

  func registerIfAuthorized() {
    guard Reception.isConfigured else { return }
    Task { await Reception.shared.registerForPushIfAuthorized() }
  }

  /// A tap that launched or reconnected the app: routed now when configured, otherwise kept until configure.
  func tap(userInfo: [AnyHashable: Any], key: String) {
    guard handlesNotifications != false, let id = Reception.pushConversationId(userInfo) else { return }
    if handlesNotifications == true {
      route(key: key, conversationId: id, openChat: true)
    } else {
      routing.queueTap(key: key, conversationId: id)
    }
  }

  /// A notification delivered through the app delegate: foreground receipt only, never a tap.
  func receive(userInfo: [AnyHashable: Any]) -> Bool {
    guard handlesNotifications == true, Reception.pushConversationId(userInfo) != nil else { return false }
    Reception.shared.handlePushNotification(userInfo: userInfo, openChat: false)
    return true
  }

  func route(key: String, conversationId: String, openChat: Bool) {
    perform(routing.action(for: key, openChat: openChat), conversationId: conversationId, openChat: openChat)
  }

  private func perform(_ action: NotificationRouting.Action, conversationId: String, openChat: Bool) {
    switch action {
    case .receive, .receiveAndOpen:
      Reception.shared.handlePushNotification(
        userInfo: ["reception": ["conversationId": conversationId]], openChat: openChat)
    case .open: Reception.shared.openChat()
    case .ignore: break
    }
  }

  static func key(_ notification: UNNotification) -> String {
    "\(notification.request.identifier)|\(notification.date.timeIntervalSince1970)"
  }

  private func applyToken() {
    guard Reception.isConfigured, let token else { return }
    Reception.shared.setPushToken(token.data, environment: token.environment)
  }

  private func installProxy() {
    let center = UNUserNotificationCenter.current()
    guard let proxy else {
      let proxy = ReceptionNotificationCenter(previous: center.delegate)
      center.delegate = proxy
      self.proxy = proxy
      return
    }
    proxy.handles = true
    if center.delegate === proxy { return }
    if center.delegate === proxy.previous {
      // Restored by an earlier opt-out; nobody replaced it since.
      center.delegate = proxy
    } else if !reportedReplacement {
      reportedReplacement = true
      Self.logger.info("Notification center delegate replaced after configure; Reception notifications are not handled")
    }
  }

  private func removeProxy() {
    guard let proxy else { return }
    proxy.handles = false
    let center = UNUserNotificationCenter.current()
    if center.delegate === proxy { center.delegate = proxy.previous }
  }
}

/// The notification-center delegate installed at configure. Handles Reception notifications and forwards everything
/// else to the delegate it replaced; every forwarded completion handler runs exactly once. UIKit calls the
/// completion-handler variants on the main thread.
@MainActor
internal final class ReceptionNotificationCenter: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
  weak var previous: UNUserNotificationCenterDelegate?
  /// False after an opt-out configure: the proxy only forwards.
  var handles = true
  private var reportedSlowPresentation = false

  init(previous: UNUserNotificationCenterDelegate?) {
    self.previous = previous
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if handles, let id = Reception.pushConversationId(notification.request.content.userInfo) {
      ReceptionNotifications.shared.route(
        key: ReceptionNotifications.key(notification), conversationId: id, openChat: false)
      completionHandler(Reception.shared.isChatOpen ? [] : [.banner, .list, .sound])
      return
    }
    // Presentation is decided at once in practice; a wrapped delegate that never answers (firebase_messaging
    // ignores calls once it no longer owns the center) must not delay the banner decision for long.
    let complete = OnceCompletion(
      fallback: [], after: .seconds(2),
      onFallback: { [weak self] in
        guard let self, !self.reportedSlowPresentation else { return }
        self.reportedSlowPresentation = true
        ReceptionNotifications.logger.info(
          "Wrapped notification delegate did not complete willPresent within 2 s; showing nothing")
      }, completionHandler)
    let forwarded: Void? = previous?.userNotificationCenter?(center, willPresent: notification) { options in
      Task { @MainActor in complete(options) }
    }
    // Without a delegate iOS shows nothing in the foreground.
    if forwarded == nil { complete([]) }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if handles, let id = Reception.pushConversationId(response.notification.request.content.userInfo) {
      if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
        ReceptionNotifications.shared.route(
          key: ReceptionNotifications.key(response.notification), conversationId: id, openChat: true)
      }
      completionHandler()
      return
    }
    let complete = OnceCompletion(fallback: (), after: .seconds(10), completionHandler)
    let forwarded: Void? = previous?.userNotificationCenter?(center, didReceive: response) {
      Task { @MainActor in complete(()) }
    }
    if forwarded == nil { complete(()) }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
    previous?.userNotificationCenter?(center, openSettingsFor: notification)
  }
}
