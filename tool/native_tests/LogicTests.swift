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
    print("NotificationRouting: receipts, taps, repeats and eviction at 64 keys passed")
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

    requests.ask = { _ in true }
    let accepted = await requests.check("accepted")
    precondition(accepted, "Dart answer must resume the request")

    var asked: [String] = []
    var answers: [String: CheckedContinuation<Bool, Never>] = [:]
    requests.ask = { id in
      asked.append(id)
      return await withCheckedContinuation { answers[id] = $0 }
    }
    let first = Task { await requests.check("first") }
    let second = Task { await requests.check("second") }
    while answers.count < 2 { await Task.yield() }
    answers["second"]?.resume(returning: true)
    answers["first"]?.resume(returning: false)
    let concurrent = await (first.value, second.value)
    precondition(!concurrent.0 && concurrent.1, "Concurrent answers must stay independent")

    answers = [:]
    let cancelled = Task { await requests.check("cancelled") }
    while answers.isEmpty { await Task.yield() }
    cancelled.cancel()
    let cancellation = await cancelled.value
    precondition(!cancellation, "SDK cancellation must release its continuation")
    answers["cancelled"]?.resume(returning: true)

    answers = [:]
    let reconnect = Task { await requests.check("reconnect") }
    while answers.isEmpty { await Task.yield() }
    requests.cancelAll()
    let reconnected = await reconnect.value
    precondition(!reconnected && requests.ask == nil, "Reconnect must drain pending requests")
    answers["reconnect"]?.resume(returning: true)
    for _ in 0..<10 { await Task.yield() }

    requests.ask = { _ in
      try? await Task.sleep(for: .seconds(60))
      return true
    }
    let started = ContinuousClock.now
    let timedOut = await requests.check("never-answers")
    let elapsed = started.duration(to: .now)
    precondition(
      !timedOut && elapsed >= .seconds(5) && elapsed < .seconds(8),
      "An unresponsive callback must time out safely")
    precondition(asked == ["first", "second", "cancelled", "reconnect"])
    print("PaywallRequests: answer, concurrency, cancellation, reconnect and timeout checks passed")
  }
}
