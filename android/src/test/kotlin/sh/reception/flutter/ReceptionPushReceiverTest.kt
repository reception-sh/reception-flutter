package sh.reception.flutter

import org.junit.Assert.assertEquals
import org.junit.Test

class ReceptionPushReceiverTest {
    @Test
    fun keepsTheMessageIdAndStringFields() {
        // The extras of a `com.google.android.c2dm.intent.RECEIVE` broadcast for a Reception reply.
        val extras = mapOf<String, Any?>(
            "google.message_id" to "0:1730745600000000%abc123",
            "google.sent_time" to 1_730_745_600_000L,
            "google.ttl" to 2_419_200,
            "google.delivered_priority" to "high",
            "from" to "123456789",
            "collapse_key" to "conv_1",
            "reception" to "conv_1",
            "title" to "Support",
            "body" to "Hi there",
            "absent" to null,
        )
        assertEquals(
            mapOf(
                "google.message_id" to "0:1730745600000000%abc123",
                "google.delivered_priority" to "high",
                "from" to "123456789",
                "collapse_key" to "conv_1",
                "reception" to "conv_1",
                "title" to "Support",
                "body" to "Hi there",
            ),
            ReceptionPushReceiver.data(extras.keys, extras::get),
        )
    }
}
