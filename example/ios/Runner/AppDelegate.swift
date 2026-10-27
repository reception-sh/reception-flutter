import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The example app's own permission prompt; the plugin never requests permission.
    // `xcrun simctl privacy` has no notifications service, so the example asks itself.
    let channel = FlutterMethodChannel(
      name: "reception_example/notifications",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "requestPermission" else { return result(FlutterMethodNotImplemented) }
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
        granted, _ in DispatchQueue.main.async { result(granted) }
      }
    }
  }
}
