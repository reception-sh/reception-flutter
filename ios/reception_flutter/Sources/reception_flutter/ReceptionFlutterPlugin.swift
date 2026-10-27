import Flutter
import UIKit

/// Registers the host API and the chat view, and receives app and scene lifecycle callbacks for push.
/// Implements no `userNotificationCenter` methods: Flutter forwards those to every plugin, so only the
/// `ReceptionNotificationCenter` proxy handles them, and completes each notification once.
public final class ReceptionFlutterPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private let host: ReceptionHost

  private init(host: ReceptionHost) {
    self.host = host
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    MainActor.assumeIsolated {
      let host = ReceptionHost(flutterApi: ReceptionFlutterApi(binaryMessenger: registrar.messenger()))
      ReceptionHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: host)
      registrar.register(ReceptionChatViewFactory(), withId: ReceptionChatViewFactory.viewType)
      let plugin = ReceptionFlutterPlugin(host: host)
      registrar.publish(plugin)
      registrar.addApplicationDelegate(plugin)
      registrar.addSceneDelegate(plugin)
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    ReceptionHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
    Task { @MainActor [host] in host.invalidate() }
  }

  public func application(
    _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any]
  ) -> Bool {
    MainActor.assumeIsolated {
      if let userInfo = launchOptions[UIApplication.LaunchOptionsKey.remoteNotification] as? [AnyHashable: Any] {
        ReceptionNotifications.shared.tap(userInfo: userInfo, key: "launch")
      }
    }
    return true
  }

  public func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    MainActor.assumeIsolated {
      guard let response = connectionOptions?.notificationResponse,
        response.actionIdentifier == UNNotificationDefaultActionIdentifier
      else { return }
      ReceptionNotifications.shared.tap(
        userInfo: response.notification.request.content.userInfo,
        key: ReceptionNotifications.key(response.notification))
    }
    return false
  }

  public func applicationDidBecomeActive(_ application: UIApplication) {
    MainActor.assumeIsolated { ReceptionNotifications.shared.registerIfAuthorized() }
  }

  public func sceneDidBecomeActive(_ scene: UIScene) {
    MainActor.assumeIsolated { ReceptionNotifications.shared.registerIfAuthorized() }
  }

  public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    MainActor.assumeIsolated { ReceptionNotifications.shared.setToken(deviceToken, environment: .automatic) }
  }

  public func application(
    _ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) -> Bool {
    MainActor.assumeIsolated {
      guard ReceptionNotifications.shared.receive(userInfo: userInfo) else { return false }
      completionHandler(.noData)
      return true
    }
  }
}
