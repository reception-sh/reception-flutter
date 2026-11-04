package sh.reception.flutter

import kotlinx.coroutines.async
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PaywallRequestsTest {
    @Test
    fun resolvesWithDartsAnswerAndIgnoresLateDuplicateAndUnknownAnswers() = runTest {
        val requests = PaywallRequests()
        val sent = mutableListOf<Pair<String, String>>()
        requests.emit = { id, paywall -> sent += id to paywall }
        val check = async { requests.check("plans") }
        runCurrent()
        assertEquals("plans", sent.single().second)
        requests.resolve("unknown", false)
        requests.resolve(sent.single().first, true)
        requests.resolve(sent.single().first, false)
        assertTrue(check.await())
    }

    @Test
    fun failsClosedAfterFiveSeconds() = runTest {
        val requests = PaywallRequests()
        val sent = mutableListOf<String>()
        requests.emit = { id, _ -> sent += id }
        val check = async { requests.check("plans") }
        advanceTimeBy(4_999)
        assertFalse(check.isCompleted)
        advanceTimeBy(2)
        assertFalse(check.await())
        requests.resolve(sent.single(), true)
    }

    @Test
    fun failsClosedWhenCancelledOrWithoutDart() = runTest {
        val requests = PaywallRequests()
        assertFalse(requests.check("plans"))
        requests.emit = { _, _ -> }
        val check = async { requests.check("plans") }
        runCurrent()
        requests.cancelAll()
        assertFalse(check.await())
        assertFalse(requests.check("plans"))
    }

    @Test
    fun cancellationByTheSdkForgetsTheRequest() = runTest {
        val requests = PaywallRequests()
        val sent = mutableListOf<String>()
        requests.emit = { id, _ -> sent += id }
        val check = async { requests.check("plans") }
        runCurrent()
        check.cancel()
        runCurrent()
        assertTrue(check.isCancelled)
        requests.resolve(sent.single(), true)
    }
}
