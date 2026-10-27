import Foundation

@main
struct LogicTests {
  @MainActor
  static func main() async {
    routing()
    pushToken()
    await onceCompletion()
    await paywallRequests()
  }

  @MainActor
  static func routing() {
    let routing = NotificationRouting()
    precondition(routing.action(for: "first", openChat: false) == .receive)
    precondition(routing.action(for: "first", openChat: false) == .ignore)
    precondition(routing.action(for: "first", openChat: true) == .open, "Receipt then tap only opens")
    precondition(routing.action(for: "first", openChat: true) == .ignore)
    precondition(routing.action(for: "first", openChat: false) == .ignore)
    precondition(routing.action(for: "cold", openChat: true) == .receiveAndOpen)
    precondition(routing.action(for: "cold", openChat: true) == .ignore)
    precondition(routing.action(for: "cold", openChat: false) == .ignore)

    let bounded = NotificationRouting()
    for index in 0..<NotificationRouting.capacity {
      precondition(bounded.action(for: "key\(index)", openChat: true) == .receiveAndOpen)
    }
    precondition(bounded.action(for: "key0", openChat: true) == .ignore, "64 keys fit")
    precondition(bounded.action(for: "key64", openChat: true) == .receiveAndOpen)
    precondition(bounded.action(for: "key0", openChat: true) == .receiveAndOpen, "Oldest key is evicted first")
    precondition(bounded.action(for: "key2", openChat: true) == .ignore, "Newer keys stay")
    precondition(bounded.action(for: "key1", openChat: true) == .receiveAndOpen, "Eviction follows insertion order")
    let launched = Date(timeIntervalSince1970: 1_000)
    let before = launched.addingTimeInterval(-60)
    let drained = launched.addingTimeInterval(2)
    let launch = NotificationRouting(launchDate: launched)
    precondition(
      launch.tapAction(for: "undrained", conversationId: "c1", deliveredAt: before, at: drained) == .receiveAndOpen,
      "Without a drained launch tap taps open")
    launch.drainedLaunchTap(conversationId: "c1", at: drained)
    precondition(
      launch.tapAction(for: "other", conversationId: "c2", deliveredAt: before, at: drained) == .receiveAndOpen,
      "Another conversation opens")
    precondition(
      launch.tapAction(for: "new", conversationId: "c1", deliveredAt: launched.addingTimeInterval(1), at: drained)
        == .receiveAndOpen, "A notification delivered after launch opens")
    precondition(
      launch.tapAction(for: "dup", conversationId: "c1", deliveredAt: before, at: drained.addingTimeInterval(1))
        == .ignore, "The launch response delivered again within 10 s is ignored")
    precondition(
      launch.tapAction(for: "dup", conversationId: "c1", deliveredAt: before, at: drained.addingTimeInterval(2))
        == .ignore, "and recorded as opened")
    precondition(
      launch.tapAction(for: "second", conversationId: "c1", deliveredAt: before, at: drained.addingTimeInterval(3))
        == .receiveAndOpen, "A second pre-launch tap opens once the marker was consumed")

    let late = NotificationRouting(launchDate: launched)
    late.drainedLaunchTap(conversationId: "c1", at: drained)
    precondition(
      late.tapAction(for: "late", conversationId: "c1", deliveredAt: before, at: drained.addingTimeInterval(11))
        == .receiveAndOpen, "A pre-launch tap 11 s after the drain opens")
    print("NotificationRouting: receipts, taps, repeats, eviction at 64 keys and launch tap dedupe passed")
  }

  static func pushToken() {
    precondition(PushToken.decode("AAbb01") == Data([0xaa, 0xbb, 1]))
    precondition(PushToken.decode(String(repeating: "ab", count: 256))?.count == 256, "512 hex chars fit")
    for token in ["", "a", "abc", "zz", "0x1f", "0a 1b", String(repeating: "a", count: 514)] {
      precondition(PushToken.decode(token) == nil, "Rejects \(token.prefix(8))")
    }
    print("PushToken: valid, odd length, non-hex and oversized tokens passed")
  }

  @MainActor
  static func onceCompletion() async {
    var values: [Int] = []
    let gate = OnceCompletion(fallback: 0, after: .milliseconds(50)) { values.append($0) }
    gate(1)
    gate(2)
    try? await Task.sleep(for: .milliseconds(150))
    precondition(values == [1], "First completion wins and cancels the fallback")

    values = []
    do {
      // Nobody keeps the gate; the fallback must still complete.
      _ = OnceCompletion(fallback: 7, after: .milliseconds(50)) { values.append($0) }
    }
    try? await Task.sleep(for: .milliseconds(150))
    precondition(values == [7], "Fallback completes an abandoned handler")

    values = []
    let late = OnceCompletion(fallback: 0, after: .milliseconds(50)) { values.append($0) }
    try? await Task.sleep(for: .milliseconds(150))
    late(3)
    precondition(values == [0], "A completion after the fallback is ignored")
    print("OnceCompletion: exactly once, fallback and late completion passed")
  }

  @MainActor
  static func paywallRequests() async {
    let requests = PaywallRequests()
    let missing = await requests.check("missing")
    precondition(!missing, "No Dart callback must fail closed")

    requests.emit = { requestId, _ in requests.resolve(requestId, allowed: true) }
    let accepted = await requests.check("accepted")
    precondition(accepted, "Dart answer must resume the matching request")

    requests.emit = { requestId, _ in
      requests.resolve(requestId, allowed: false)
      requests.resolve(requestId, allowed: true)
    }
    let duplicate = await requests.check("duplicate")
    precondition(!duplicate, "A duplicate answer must not resume twice")

    var asked: [String: String] = [:]
    requests.emit = { requestId, paywall in asked[paywall] = requestId }
    let first = Task { await requests.check("first") }
    let second = Task { await requests.check("second") }
    while asked.count < 2 { await Task.yield() }
    precondition(asked["first"] != asked["second"], "Requests must have independent IDs")
    requests.resolve("unknown", allowed: true)
    requests.resolve(asked["second"]!, allowed: true)
    requests.resolve(asked["first"]!, allowed: false)
    let concurrent = await (first.value, second.value)
    precondition(!concurrent.0 && concurrent.1, "Concurrent answers must stay independent")

    asked = [:]
    let cancelled = Task { await requests.check("cancelled") }
    while asked.isEmpty { await Task.yield() }
    cancelled.cancel()
    let cancellation = await cancelled.value
    precondition(!cancellation, "SDK cancellation must release its continuation")
    requests.resolve(asked["cancelled"]!, allowed: true)

    asked = [:]
    let reconnect = Task { await requests.check("reconnect") }
    while asked.isEmpty { await Task.yield() }
    requests.cancelAll()
    let reconnected = await reconnect.value
    precondition(!reconnected && requests.emit == nil, "Reconnect must drain pending requests")
    requests.resolve(asked["reconnect"]!, allowed: true)

    asked = [:]
    requests.emit = { requestId, paywall in asked[paywall] = requestId }
    let started = ContinuousClock.now
    let timedOut = await requests.check("never-answers")
    let elapsed = started.duration(to: .now)
    precondition(
      !timedOut && elapsed >= .seconds(5) && elapsed < .seconds(8),
      "An unresponsive callback must time out safely")
    requests.resolve(asked["never-answers"]!, allowed: true)

    // The late answers above resolved nothing: the next request still gets its own answer.
    requests.emit = { requestId, _ in requests.resolve(requestId, allowed: true) }
    let next = await requests.check("next")
    precondition(next, "Late answers must not affect later requests")
    print("PaywallRequests: answer, duplicate, unknown, concurrency, cancellation, reconnect, timeout and late answer checks passed")
  }
}
