package sh.reception.flutter

import android.util.Log
import java.net.URI
import java.net.URISyntaxException

/** What a configure from Dart changes, in order. [ReceptionHost] runs the steps against the SDK. */
internal interface ConfigureSteps {
    /** Notification icon and tap routing, before the SDK configures: a pending tap must see the new routing. */
    fun prepare(handlesNotifications: Boolean, notificationSmallIcon: String?)

    /** Configures the SDK; [serviceUrl] is null for the production service. */
    fun configure(appId: String, serviceUrl: String?)

    /** After the SDK configured: stores the receiver opt-out and hands the push token on. */
    fun configured(handlesNotifications: Boolean)

    /** A configure the SDK would refuse; changes nothing beyond letting the SDK log why. */
    fun refused(appId: String)
}

/**
 * A configure from Dart, validated with the SDK's rules before anything changes, so a refused one leaves the earlier
 * configuration, its notification routing, the stored opt-out and a pending tap exactly as they were.
 */
internal class ConfigureRequest(
    private val appId: String,
    private val serviceUrl: String?,
    private val handlesNotifications: Boolean,
    private val notificationSmallIcon: String?,
) {
    companion object {
        /** The SDK's App ID rule. */
        private val appIdPattern = Regex("^app_[A-Za-z0-9]{22}$")

        // 10.0.2.2 is the development machine's loopback as seen from the Android emulator.
        private val loopbackHosts = setOf("localhost", "127.0.0.1", "::1", "[::1]", "10.0.2.2")

        private const val TAG = "ReceptionFlutter"

        /**
         * A testing service must be an http(s) URL on a loopback host, and only debuggable apps may use one. The port
         * follows OkHttp's `HttpUrl` (the SDK's parser, not on this module's compile classpath): omitted or 1..65535.
         */
        fun acceptsTestingService(serviceUrl: String, debuggable: Boolean): Boolean {
            if (!debuggable) return false
            val uri = try {
                URI(serviceUrl)
            } catch (_: URISyntaxException) {
                return false
            }
            // OkHttp lowercases scheme and host.
            return uri.scheme?.lowercase() in setOf("http", "https") &&
                uri.host?.lowercase() in loopbackHosts &&
                (uri.port == -1 || uri.port in 1..65535)
        }
    }

    /** Runs [steps] when the SDK accepts this configure; returns whether it did. */
    fun run(steps: ConfigureSteps, debuggable: Boolean): Boolean {
        if (!appIdPattern.matches(appId)) {
            steps.refused(appId)
            return false
        }
        if (serviceUrl != null && !acceptsTestingService(serviceUrl, debuggable)) {
            Log.d(TAG, "configureForTesting refused the service URL")
            return false
        }
        steps.prepare(handlesNotifications, notificationSmallIcon)
        steps.configure(appId, serviceUrl)
        steps.configured(handlesNotifications)
        return true
    }
}
