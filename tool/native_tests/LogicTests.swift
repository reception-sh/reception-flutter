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
    let launch = NotificationRouting(launchDate: launched)
    precondition(
      launch.tapAction(for: "undrained", conversationId: "c1", deliveredAt: launched.addingTimeInterval(-5))
        == .receiveAndOpen, "Without a drained launch tap taps open")
    precondition(launch.action(for: "launch", openChat: true) == .receiveAndOpen)
    launch.drainedLaunchTap(conversationId: "c1")
    precondition(
      launch.tapAction(for: "same", conversationId: "c1", deliveredAt: launched.addingTimeInterval(-5)) == .ignore,
      "The launch tap delivered again through the proxy is ignored")
    precondition(
      launch.tapAction(for: "same", conversationId: "c1", deliveredAt: launched.addingTimeInterval(-5)) == .ignore,
      "and recorded as opened")
    precondition(
      launch.tapAction(for: "new", conversationId: "c1", deliveredAt: launched.addingTimeInterval(1))
        == .receiveAndOpen, "A notification delivered after launch opens")
    precondition(
      launch.tapAction(for: "other", conversationId: "c2", deliveredAt: launched.addingTimeInterval(-5))
        == .receiveAndOpen, "Another conversation opens")
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

    requests.ask = { _, reply in reply(true) }
    let accepted = await requests.check("accepted")
    precondition(accepted, "Dart answer must resume the request")

    requests.ask = { _, reply in
      reply(false)
      reply(true)
    }
    let duplicate = await requests.check("duplicate")
    precondition(!duplicate, "A duplicate reply must not resume twice")

    var asked: [String] = []
    var replies: [String: @Sendable (Bool) -> Void] = [:]
    requests.ask = { id, reply in
      asked.append(id)
      replies[id] = reply
    }
    let first = Task { await requests.check("first") }
    let second = Task { await requests.check("second") }
    while replies.count < 2 { await Task.yield() }
    replies["second"]?(true)
    replies["first"]?(false)
    let concurrent = await (first.value, second.value)
    precondition(!concurrent.0 && concurrent.1, "Concurrent answers must stay independent")

    replies = [:]
    let cancelled = Task { await requests.check("cancelled") }
    while replies.isEmpty { await Task.yield() }
    cancelled.cancel()
    let cancellation = await cancelled.value
    precondition(!cancellation, "SDK cancellation must release its continuation")
    replies["cancelled"]?(true)
    await settle()

    replies = [:]
    let reconnect = Task { await requests.check("reconnect") }
    while replies.isEmpty { await Task.yield() }
    requests.cancelAll()
    let reconnected = await reconnect.value
    precondition(!reconnected && requests.ask == nil, "Reconnect must drain pending requests")
    replies["reconnect"]?(true)
    await settle()

    var late: (@Sendable (Bool) -> Void)?
    requests.ask = { _, reply in late = reply }
    let started = ContinuousClock.now
    let timedOut = await requests.check("never-answers")
    let elapsed = started.duration(to: .now)
    precondition(
      !timedOut && elapsed >= .seconds(5) && elapsed < .seconds(8),
      "An unresponsive callback must time out safely")
    late?(true)
    await settle()

    // Late replies above resolved nothing: the next request still gets its own answer.
    requests.ask = { _, reply in DispatchQueue.global().async { reply(true) } }
    let offMain = await requests.check("off-main")
    precondition(offMain, "A reply from another thread resolves on the main actor")
    precondition(asked == ["first", "second", "cancelled", "reconnect"])
    print("PaywallRequests: answer, duplicate, concurrency, cancellation, reconnect, timeout and late reply checks passed")
  }

  @MainActor
  static func settle() async {
    for _ in 0..<10 { await Task.yield() }
  }
}
