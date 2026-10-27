import Foundation

/// Asks Dart whether a paywall is available. Every request fails closed: after five seconds, when the SDK cancels
/// it, or when `cancelAll()` runs because the callback changed or the Dart connection was replaced.
@MainActor
internal final class PaywallRequests {
  private struct Pending {
    let continuation: CheckedContinuation<Bool, Never>
    let timeout: Task<Void, Never>
  }
  private var pending: [UUID: Pending] = [:]
  var ask: (@MainActor (String) async -> Bool)?

  func check(_ paywall: String) async -> Bool {
    guard !Task.isCancelled, ask != nil else { return false }
    let requestId = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard !Task.isCancelled, let ask else {
          continuation.resume(returning: false)
          return
        }
        let timeout = Task { [weak self] in
          do { try await Task.sleep(for: .seconds(5)) } catch { return }
          self?.resolve(requestId, allowed: false)
        }
        pending[requestId] = Pending(continuation: continuation, timeout: timeout)
        Task { [weak self] in
          let allowed = await ask(paywall)
          self?.resolve(requestId, allowed: allowed)
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.resolve(requestId, allowed: false) }
    }
  }

  func cancelAll() {
    for requestId in Array(pending.keys) { resolve(requestId, allowed: false) }
    ask = nil
  }

  private func resolve(_ requestId: UUID, allowed: Bool) {
    guard let request = pending.removeValue(forKey: requestId) else { return }
    request.timeout.cancel()
    request.continuation.resume(returning: allowed)
  }
}
