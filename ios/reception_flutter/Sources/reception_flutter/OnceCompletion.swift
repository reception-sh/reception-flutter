/// Calls a notification-center completion handler exactly once: the first call wins, and `fallback` is delivered
/// after `timeout` if nobody completed, so a delegate we forward to cannot leave iOS waiting.
@MainActor
internal final class OnceCompletion<Value: Sendable> {
  private var completion: ((Value) -> Void)?
  private var timer: Task<Void, Never>?

  init(fallback: Value, after timeout: Duration = .seconds(10), _ completion: @escaping (Value) -> Void) {
    self.completion = completion
    // Holds the gate until it completes, even if the delegate we forwarded to dropped its handler.
    timer = Task {
      do { try await Task.sleep(for: timeout) } catch { return }
      self.callAsFunction(fallback)
    }
  }

  func callAsFunction(_ value: Value) {
    guard let completion else { return }
    self.completion = nil
    timer?.cancel()
    completion(value)
  }
}
