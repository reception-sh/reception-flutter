package sh.reception.flutter

import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID
import kotlin.coroutines.resume

/**
 * Asks Dart whether a paywall is available. [emit] sends a request id that Dart answers through
 * `resolvePaywallAvailability`. Every request fails closed: after five seconds, when the SDK cancels it, or when
 * [cancelAll] runs because the callback changed or the Dart connection was replaced. Late, duplicate and unknown
 * answers are ignored. Main thread only.
 */
internal class PaywallRequests(private val timeoutMillis: Long = 5_000) {
    private val pending = mutableMapOf<String, CancellableContinuation<Boolean>>()
    var emit: ((requestId: String, paywall: String) -> Unit)? = null

    suspend fun check(paywall: String): Boolean {
        val emit = emit ?: return false
        val requestId = UUID.randomUUID().toString()
        return withTimeoutOrNull(timeoutMillis) {
            suspendCancellableCoroutine { continuation ->
                pending[requestId] = continuation
                // A timeout or the SDK's cancellation; both run on the main thread.
                continuation.invokeOnCancellation { pending.remove(requestId) }
                emit(requestId, paywall)
            }
        } ?: false
    }

    fun resolve(requestId: String, allowed: Boolean) {
        pending.remove(requestId)?.resume(allowed)
    }

    fun cancelAll() {
        for (requestId in pending.keys.toList()) resolve(requestId, false)
        emit = null
    }
}
