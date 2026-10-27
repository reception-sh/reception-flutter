import Foundation

/// Asks Dart whether a paywall is available. `emit` sends a request id that Dart answers through
/// `resolvePaywallAvailability`. Every request fails closed: after five seconds, when the SDK cancels it, or when
/// `cancelAll()` runs because the callback changed or the Dart connection was replaced. Late, duplicate and unknown
/// answers are ignored.
@MainActor
internal final class PaywallRequests {
  private struct Pending {
    let continuation: CheckedContinuation<Bool, Never>
    let timeout: Task<Void, Never>
  }
  private var pending: [String: Pending] = [:]
  var emit: ((_ requestId: String, _ paywall: String) -> Void)?

  func check(_ paywall: String) async -> Bool {
    guard !Task.isCancelled, emit != nil else { return false }
    let requestId = UUID().uuidString
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard !Task.isCancelled, let emit else {
          continuation.resume(returning: false)
          return
        }
        let timeout = Task { [weak self] in
          do { try await Task.sleep(for: .seconds(5)) } catch { return }
          self?.resolve(requestId, allowed: false)
        }
        pending[requestId] = Pending(continuation: continuation, timeout: timeout)
        emit(requestId, paywall)
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.resolve(requestId, allowed: false) }
    }
  }

  func resolve(_ requestId: String, allowed: Bool) {
    guard let request = pending.removeValue(forKey: requestId) else { return }
    request.timeout.cancel()
    request.continuation.resume(returning: allowed)
  }

  func cancelAll() {
    for requestId in Array(pending.keys) { resolve(requestId, allowed: false) }
    emit = nil
  }
}
