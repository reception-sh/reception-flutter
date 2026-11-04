package sh.reception.flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import sh.reception.Reception

/**
 * Receives every FCM message of the app (`com.google.android.c2dm.intent.RECEIVE`), beside Firebase's own receiver and
 * firebase_messaging's, and shows Reception replies natively through the SDK, even when the process was started for
 * the message and no Dart code runs. It never consumes the broadcast, so other messages reach the app's Firebase
 * handlers unchanged. See PUSH-DESIGN.md "Android".
 */
public class ReceptionPushReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val data = intent.extras?.let(::data) ?: return
        if (!data.containsKey(PAYLOAD_KEY) || !ReceptionNotifications.handlesNotifications(context)) return
        Reception.handlePushMessage(context, data)
    }

    internal companion object {
        /** `brand.pushPayloadKey` of the service: the conversation id of a Reception reply. */
        const val PAYLOAD_KEY = "reception"

        /**
         * The message's string fields; FCM sends data fields as string extras. It keeps `google.message_id`, by which
         * the SDK drops a message delivered again (for example to the receiver and the app's Firebase service).
         */
        fun data(extras: Bundle): Map<String, String> = data(extras.keySet()) { key -> @Suppress("DEPRECATION") extras.get(key) }

        /** [data] over the extras' [keys] and their values; non-string values (FCM's `google.sent_time`, …) are dropped. */
        fun data(keys: Iterable<String>, value: (String) -> Any?): Map<String, String> =
            keys.mapNotNull { key -> (value(key) as? String)?.let { key to it } }.toMap()
    }
}
