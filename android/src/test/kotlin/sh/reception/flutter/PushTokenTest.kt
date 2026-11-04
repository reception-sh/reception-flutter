package sh.reception.flutter

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PushTokenTest {
    @Test
    fun acceptsFcmTokensOnly() {
        assertTrue(PushToken.isValid("dQw4w9WgXcQ:APA91bH-abc_DEF123"))
        assertTrue(PushToken.isValid("a".repeat(4096)))
        for (token in listOf("", "a".repeat(4097), "has space", "ExpoPushToken[x]", "ä")) assertFalse(PushToken.isValid(token))
    }
}
