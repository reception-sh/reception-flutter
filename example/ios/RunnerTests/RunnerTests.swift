import XCTest

@testable import reception_flutter

/// Compiles against the plugin as the app builds it and checks logic that needs no running Flutter engine.
final class RunnerTests: XCTestCase {
  func testPushTokenDecoding() {
    XCTAssertEqual(PushToken.decode("AAbb01"), Data([0xaa, 0xbb, 0x01]))
    XCTAssertNil(PushToken.decode("abc"))
  }

  @MainActor
  func testNotificationRoutingOpensOnce() {
    let routing = NotificationRouting()
    XCTAssertEqual(routing.action(for: "tap", openChat: true), .receiveAndOpen)
    XCTAssertEqual(routing.action(for: "tap", openChat: true), .ignore)
  }
}
