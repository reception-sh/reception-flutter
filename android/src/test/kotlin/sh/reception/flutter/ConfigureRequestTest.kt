package sh.reception.flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ConfigureRequestTest {
    private class RecordingSteps : ConfigureSteps {
        val calls = mutableListOf<String>()

        override fun prepare(handlesNotifications: Boolean, notificationSmallIcon: String?) {
            calls += "prepare($handlesNotifications, $notificationSmallIcon)"
        }

        override fun configure(appId: String, serviceUrl: String?) {
            calls += "configure($appId, $serviceUrl)"
        }

        override fun configured(handlesNotifications: Boolean) {
            calls += "configured($handlesNotifications)"
        }

        override fun refused(appId: String) {
            calls += "refused($appId)"
        }
    }

    private val appId = "app_lQCXNRFINXc8FEnriGpad3"
    private val serviceUrl = "http://10.0.2.2:3123"

    @Test
    fun aRefusedConfigureAfterAValidOneChangesNothing() {
        val steps = RecordingSteps()
        assertTrue(ConfigureRequest(appId, serviceUrl, true, "ic_stat").run(steps, debuggable = true))
        val valid = listOf("prepare(true, ic_stat)", "configure($appId, $serviceUrl)", "configured(true)")
        assertEquals(valid, steps.calls)

        // Each would turn notification handling off; none may reach routing, the stored opt-out or the SDK's URL.
        val refused = listOf(
            ConfigureRequest("app_short", serviceUrl, false, null) to true,
            ConfigureRequest("ids_lQCXNRFINXc8FEnriGpad3", serviceUrl, false, null) to true,
            ConfigureRequest("app_short", null, false, null) to true,
            ConfigureRequest(appId, "http://example.com:3123", false, null) to true,
            ConfigureRequest(appId, "ftp://localhost:3123", false, null) to true,
            ConfigureRequest(appId, "not a url", false, null) to true,
            // java.net.URI accepts port 0; OkHttp, the SDK's parser, does not.
            ConfigureRequest(appId, "http://10.0.2.2:0", false, null) to true,
            ConfigureRequest(appId, serviceUrl, false, null) to false,
        )
        for ((request, debuggable) in refused) assertFalse(request.run(steps, debuggable))
        assertEquals(
            valid + listOf(
                "refused(app_short)", "refused(ids_lQCXNRFINXc8FEnriGpad3)", "refused(app_short)",
            ),
            steps.calls,
        )
    }

    @Test
    fun productionConfigureNeedsNoDebuggableApp() {
        val steps = RecordingSteps()
        assertTrue(ConfigureRequest(appId, null, false, null).run(steps, debuggable = false))
        assertEquals(listOf("prepare(false, null)", "configure($appId, null)", "configured(false)"), steps.calls)
    }

    @Test
    fun testingServiceRule() {
        for (url in listOf(
            "http://localhost:3123", "https://127.0.0.1", "http://[::1]:3123/", "http://10.0.2.2:3123/api",
            "http://localhost:1", "http://localhost:65535", "HTTP://LocalHost:3123",
        )) assertTrue(url, ConfigureRequest.acceptsTestingService(url, debuggable = true))
        for (url in listOf(
            "http://localhost:99999", "http://localhost:0", "http://localhost:65536", "http://reception.sh", "localhost:3123", "http://LOCAL HOST", "",
        )) assertFalse(url, ConfigureRequest.acceptsTestingService(url, debuggable = true))
        assertFalse(ConfigureRequest.acceptsTestingService("http://localhost:3123", debuggable = false))
    }
}
