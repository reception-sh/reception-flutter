package sh.reception.flutter

import android.content.Context
import sh.reception.Reception

/**
 * Process-wide push support: keeps the FCM token Dart passed across configure, logout and deletion, and remembers
 * whether the app lets the plugin handle Reception messages, so [ReceptionPushReceiver] knows it before Dart runs.
 * Taps and their routing belong to the SDK (its notification activity). Main thread only.
 */
internal object ReceptionNotifications {
    private const val PREFERENCES = "sh.reception.flutter"
    private const val HANDLES_NOTIFICATIONS = "handlesNotifications"
    private var token: String? = null

    fun setToken(token: String) {
        this.token = token
        applyToken()
    }

    /** Called after every configure from Dart that the SDK accepted. */
    fun configured(context: Context, handlesNotifications: Boolean) {
        if (!Reception.isConfigured) return
        preferences(context).edit().putBoolean(HANDLES_NOTIFICATIONS, handlesNotifications).apply()
        applyToken()
    }

    /** Hands the token from Dart to the SDK again: logout and deletion clear its staged token. The SDK itself asks
     *  Firebase for the token again when notifications are allowed. */
    fun restorePush() = applyToken()

    /** False after the latest configure opted out with `handlesNotifications: false`; true before any configure. */
    fun handlesNotifications(context: Context): Boolean = preferences(context).getBoolean(HANDLES_NOTIFICATIONS, true)

    private fun applyToken() {
        val token = token ?: return
        if (Reception.isConfigured) Reception.setPushToken(token)
    }

    private fun preferences(context: Context) = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
}
