package sh.reception.flutter

import android.content.Context
import android.content.pm.ApplicationInfo
import android.net.Uri
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import sh.reception.Reception
import sh.reception.ReceptionError
import sh.reception.ReceptionEvent
import sh.reception.ReceptionInternalApi
import sh.reception.ReceptionScreen
import java.lang.ref.WeakReference

/**
 * Implements the Pigeon host API for one Flutter engine. The SDK is a process-wide singleton, so only the most recently
 * connected engine receives state, events and callbacks; `connect()` replaces any earlier connection, including the
 * same engine's after a hot restart. Pigeon calls on the main thread.
 */
internal class ReceptionHost(private val context: Context, private val flutterApi: ReceptionFlutterApi) : ReceptionHostApi {
    private companion object {
        var current: WeakReference<ReceptionHost>? = null
        var revision = 0L
        val appIdPattern = Regex("^app_[A-Za-z0-9]{22}$")
        val loopbackHosts = setOf("localhost", "127.0.0.1", "::1", "[::1]", "10.0.2.2")
        val logLevels = mapOf(
            "off" to Reception.LogLevel.OFF, "error" to Reception.LogLevel.ERROR,
            "info" to Reception.LogLevel.INFO, "debug" to Reception.LogLevel.DEBUG,
        )
    }

    private val requests = PaywallRequests()

    /** Work that outlives a connection, such as a deletion Dart awaits. */
    private val scope = MainScope()
    private var connected = false
    private var settingRevisions = mutableMapOf<String, Long>()

    /** The current connection's state observation and calls to Dart; cancelled when the connection ends. */
    private var connection: CoroutineScope? = null

    fun invalidate() {
        connected = false
        connection?.cancel()
        connection = null
        requests.cancelAll()
        if (current?.get() !== this) return
        Reception.onEvent = null
        Reception.onPaywall = null
        // Without Dart nothing can open a screen, so none is reported until Dart lists them again.
        Reception.screens = emptyList()
        // A missing Dart callback must not turn a previously filtered offer into an available one.
        if (Reception.paywallAvailability != null) Reception.paywallAvailability = { false }
        current = null
    }

    /** Only the current connection may change SDK callbacks; a replaced engine or connection must not. */
    private val isCurrent: Boolean
        get() = connected && current?.get() === this

    private fun snapshot(): SnapshotMessage {
        revision += 1
        return SnapshotMessage(
            revision = revision, settingRevisions = settingRevisions.toMap(), isConfigured = Reception.isConfigured,
            unreadCount = Reception.unreadCount.value.toLong(), isChatOpen = Reception.isChatOpen.value,
            availablePaywalls = Reception.availablePaywalls.map(PaywallValues::message),
            paywalls = Reception.paywalls.map(PaywallValues::message),
            appearanceJson = ReceptionAppearance.values.toString(),
            updatesAppBadge = Reception.updatesAppBadge, usesRemoteAppearance = Reception.usesRemoteAppearance,
            opensWebLinksInApp = Reception.opensWebLinksInApp, languageOverride = Reception.languageOverride,
            logLevel = logLevels.entries.first { it.value == Reception.logLevel }.key,
        )
    }

    private fun applySetting(key: String, revision: Long, update: () -> Unit): SnapshotMessage {
        if (connected && revision > (settingRevisions[key] ?: 0)) {
            update()
            settingRevisions[key] = revision
        }
        return snapshot()
    }

    /** Publishes a snapshot now and after every change of the SDK state that Dart mirrors. */
    private fun observe(scope: CoroutineScope) {
        SnapshotNotifications.start()
        scope.launch {
            combine(Reception.unreadCount, Reception.isChatOpen, snapshotFlow { Reception.availablePaywalls }) { _, _, _ -> }
                .collect { send { onState(snapshot()) } }
        }
    }

    /** Calls Dart on the current connection; a failed or cancelled call is dropped. */
    private fun send(call: suspend ReceptionFlutterApi.() -> Unit) {
        val scope = connection ?: return
        scope.launch {
            try {
                flutterApi.call()
            } catch (_: ReceptionBridgeError) {
                // Dart is gone or replaced; the next connection reads a fresh snapshot.
            }
        }
    }

    private fun send(event: ReceptionEvent) {
        val message = when (event) {
            is ReceptionEvent.IdentityRejected ->
                EventMessage("identityRejected", ErrorMessage(event.error.code, event.error.status.toLong()))
            ReceptionEvent.ChatOpened -> EventMessage("chatOpened")
            ReceptionEvent.MessageSent -> EventMessage("messageSent")
            ReceptionEvent.ImageSent -> EventMessage("imageSent")
            ReceptionEvent.ReviewOpened -> EventMessage("reviewOpened")
            ReceptionEvent.PaywallOpened -> EventMessage("paywallOpened")
            ReceptionEvent.LinkOpened -> EventMessage("linkOpened")
            ReceptionEvent.DataDeleted -> EventMessage("dataDeleted")
        }
        send { onEvent(message) }
    }

    // ReceptionHostApi

    override fun version(): String = Reception.version

    override fun connect(): SnapshotMessage {
        current?.get()?.invalidate()
        current = WeakReference(this)
        connected = true
        connection?.cancel()
        connection = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate).also(::observe)
        // Dart counts setting revisions from zero again after a hot restart.
        settingRevisions = mutableMapOf()
        Reception.onEvent = { event -> send(event) }
        return snapshot()
    }

    override fun configure(appId: String, handlesNotifications: Boolean): SnapshotMessage {
        // The SDK logs why it refuses a malformed App ID; a refused one leaves any earlier configuration unchanged.
        Reception.configure(context, appId)
        if (appIdPattern.matches(appId)) ReceptionNotifications.configured(context, handlesNotifications)
        return snapshot()
    }

    @OptIn(ReceptionInternalApi::class)
    override fun configureForTesting(appId: String, serviceUrl: String): SnapshotMessage {
        val uri = Uri.parse(serviceUrl)
        val debuggable = context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        // 10.0.2.2 is the development machine's loopback as seen from the Android emulator.
        if (debuggable && uri.scheme in setOf("http", "https") && uri.host in loopbackHosts) {
            Reception.configureForTesting(context, appId, serviceUrl)
            ReceptionNotifications.configured(context, handlesNotifications = true)
        }
        return snapshot()
    }

    override fun identify(userId: String?, name: String?, email: String?) = Reception.identify(userId, name, email)

    override fun identifyToken(token: String) = Reception.identifyWithToken(token)

    override fun setMetadata(metadata: Map<String, String>) = Reception.setMetadata(metadata)

    override fun logout(): SnapshotMessage {
        Reception.logout()
        ReceptionNotifications.restorePush()
        return snapshot()
    }

    override fun deleteData(callback: (Result<DeleteResultMessage>) -> Unit) {
        scope.launch {
            val error = try {
                Reception.deleteData()
                ReceptionNotifications.restorePush()
                null
            } catch (error: ReceptionError) {
                ErrorMessage(error.code, error.status.toLong())
            } catch (_: Exception) {
                ErrorMessage("bridge_error", 0)
            }
            callback(Result.success(DeleteResultMessage(snapshot(), error)))
        }
    }

    override fun openChat() = Reception.openChat()

    override fun closeChat() = Reception.closeChat()

    override fun track(event: String, opensChat: Boolean) = Reception.track(event, opensChat)

    /** Android has no push environment; the token is an FCM registration token. */
    override fun setPushToken(hexToken: String, environment: String) {
        if (PushToken.isValid(hexToken)) ReceptionNotifications.setToken(hexToken)
    }

    override fun registerForPushIfAuthorized(callback: (Result<Unit>) -> Unit) {
        Reception.registerForPushIfAuthorized()
        callback(Result.success(Unit))
    }

    override fun handlePushNotification(conversationId: String, openChat: Boolean): Boolean =
        Reception.handlePushNotification(mapOf(ReceptionPushReceiver.PAYLOAD_KEY to conversationId), openChat)

    override fun setAppearance(json: String, revision: Long) =
        applySetting("appearance", revision) { ReceptionAppearance.apply(context, json) }

    override fun setUpdatesAppBadge(value: Boolean, revision: Long) =
        applySetting("updatesAppBadge", revision) { Reception.updatesAppBadge = value }

    override fun setUsesRemoteAppearance(value: Boolean, revision: Long) =
        applySetting("usesRemoteAppearance", revision) { Reception.usesRemoteAppearance = value }

    override fun setOpensWebLinksInApp(value: Boolean, revision: Long) =
        applySetting("opensWebLinksInApp", revision) { Reception.opensWebLinksInApp = value }

    override fun setLanguageOverride(value: String?, revision: Long) =
        applySetting("languageOverride", revision) { Reception.languageOverride = value }

    override fun setLogLevel(value: String, revision: Long) =
        applySetting("logLevel", revision) { logLevels[value]?.let { Reception.logLevel = it } }

    override fun setPaywalls(value: List<PaywallMessage>, revision: Long) =
        applySetting("paywalls", revision) { Reception.paywalls = value.map(PaywallValues::paywall) }

    override fun setPaywallHandler(enabled: Boolean) {
        if (!isCurrent) return
        Reception.onPaywall = if (enabled) { id -> send { onPaywall(id) } } else null
    }

    /** Dart validated the list; each screen forwards its ID and value, and Dart runs the matching open. */
    override fun setScreens(screens: List<ScreenMessage>) {
        if (!isCurrent) return
        Reception.screens = screens.map { screen ->
            val value = screen.value
            if (value != null) {
                ReceptionScreen(screen.id, value) { given -> openScreen(screen.id, given) }
            } else {
                ReceptionScreen(screen.id) { openScreen(screen.id, null) }
            }
        }
    }

    /** The chat has closed; Dart gets that state before the screen's callback, so `isChatOpen` already reads false. */
    private fun openScreen(id: String, value: String?) {
        if (!isCurrent) return
        val state = snapshot()
        // Runs in the connection's scope, so a reconnect during the first call cancels the second.
        send {
            onState(state)
            if (isCurrent && kotlin.coroutines.coroutineContext.isActive) onScreen(id, value)
        }
    }

    override fun setPaywallAvailability(enabled: Boolean, generation: Long): SnapshotMessage {
        if (!isCurrent) return snapshot()
        requests.cancelAll()
        if (!enabled) {
            Reception.paywallAvailability = null
            return snapshot()
        }
        requests.emit = { requestId, id -> send { requestPaywallAvailability(requestId, id, generation) } }
        Reception.paywallAvailability = { id -> connected && requests.check(id) }
        return snapshot()
    }

    override fun resolvePaywallAvailability(requestId: String, allowed: Boolean) = requests.resolve(requestId, allowed)

    override fun refreshPaywalls(invalidate: Boolean) = Reception.refreshPaywalls(invalidate)
}
