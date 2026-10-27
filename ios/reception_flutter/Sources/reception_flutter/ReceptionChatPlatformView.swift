import Flutter
import SwiftUI

/// Creates the embedded chat for `ReceptionChatView` widgets (`UiKitView(viewType: 'reception_flutter/chat')`).
internal final class ReceptionChatViewFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "reception_flutter/chat"

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    MainActor.assumeIsolated { ReceptionChatPlatformView(frame: frame) }
  }
}

/// Hosts the SDK's SwiftUI chat in a child view controller of the nearest view controller while in a window.
internal final class ReceptionChatPlatformView: UIView, FlutterPlatformView {
  private var host: UIHostingController<ReceptionChatView>?

  nonisolated func view() -> UIView { self }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil, host == nil {
      guard let parent = nearestViewController() else { return }
      clipsToBounds = true
      let controller = UIHostingController(rootView: ReceptionChatView())
      controller.view.backgroundColor = .clear
      parent.addChild(controller)
      addSubview(controller.view)
      controller.view.frame = bounds
      controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      controller.didMove(toParent: parent)
      host = controller
    } else if window == nil, let controller = host {
      controller.willMove(toParent: nil)
      controller.view.removeFromSuperview()
      controller.removeFromParent()
      host = nil
    }
  }

  private func nearestViewController() -> UIViewController? {
    var responder: UIResponder? = next
    while let current = responder {
      if let controller = current as? UIViewController { return controller }
      responder = current.next
    }
    return nil
  }
}
