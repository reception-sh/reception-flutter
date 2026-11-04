package sh.reception.flutter

import android.content.Context
import android.content.res.Configuration
import android.util.Log
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import org.json.JSONException
import org.json.JSONObject
import sh.reception.Reception

/** Applies the appearance JSON from Dart to the SDK. Main thread only. */
internal object ReceptionAppearance {
    /** The appearance JSON last accepted from Dart, returned in snapshots. */
    var values: JSONObject = JSONObject()
        private set

    fun apply(context: Context, json: String) {
        val values = try {
            JSONObject(json)
        } catch (_: JSONException) {
            return
        }
        val accepted = JSONObject(json)
        val style = Reception.Appearance()
        val dark = when (values.opt("preferredColorScheme")) {
            "light" -> false
            "dark" -> true
            else -> context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        }
        // The SDK takes one color per property; a light/dark pair resolves for the scheme in effect now.
        fun color(key: String): Color? = ReceptionColor.decode(plain(values.opt(key)))?.let { Color(if (dark) it.dark else it.light) }
        fun text(key: String): String? = values.opt(key) as? String
        fun flag(key: String): Boolean? = values.opt(key) as? Boolean
        fun number(key: String, range: ClosedFloatingPointRange<Double>): Double? =
            (values.opt(key) as? Number)?.toDouble()?.takeIf { it.isFinite() && it in range }
        // An asset that cannot be found keeps the earlier value, so a working customization stays.
        fun keepPrevious(key: String, message: String) {
            Log.e(TAG, message)
            if (this.values.has(key)) accepted.put(key, this.values.get(key)) else accepted.remove(key)
        }

        style.accentColor = color("accentColor")
        style.onAccentColor = color("onAccentColor")
        style.chatBackground = color("chatBackground")
        style.incomingBackground = color("incomingBackground")
        style.incomingForeground = color("incomingForeground")
        style.welcomeIconColor = color("welcomeIconColor")
        text("title")?.let { style.title = it }
        text("welcomeTitle")?.let { style.welcomeTitle = it }
        text("welcomeText")?.let { style.welcomeText = it }
        flag("showsCloseButton")?.let { style.showsCloseButton = it }
        flag("fadesOlderMessages")?.let { style.fadesOlderMessages = it }
        flag("hidesTitle")?.let { style.hidesTitle = it }
        flag("hidesWelcomeTitle")?.let { style.hidesWelcomeTitle = it }
        flag("hidesWelcomeText")?.let { style.hidesWelcomeText = it }
        flag("hidesPushStatus")?.let { style.hidesPushStatus = it }
        Reception.CloseIcon.entries.firstOrNull { closeIconName(it) == text("closeIcon") }?.let { style.closeIcon = it }
        style.preferredColorScheme = when (text("preferredColorScheme")) {
            "light" -> Reception.ColorScheme.LIGHT
            "dark" -> Reception.ColorScheme.DARK
            else -> null
        }
        style.fontDesign = when (text("fontDesign")) {
            "default" -> Reception.FontDesign.DEFAULT
            "rounded" -> Reception.FontDesign.ROUNDED
            "serif" -> Reception.FontDesign.SERIF
            "monospaced" -> Reception.FontDesign.MONOSPACED
            else -> null
        }
        text("fontFamily")?.let { name ->
            val family = ReceptionAssets.fontFamily(context, name)
            if (family != null) {
                style.fontFamily = family
            } else {
                keepPrevious("fontFamily", "Font family not in the app's pubspec.yaml ignored")
                style.fontFamily = Reception.appearance.fontFamily
            }
        }
        number("welcomeIconSize", 16.0..160.0)?.let { style.welcomeIconSize = it.dp }
        number("welcomeIconCornerRadius", 0.0..80.0)?.let { style.welcomeIconCornerRadius = it.dp }
        (values.opt("welcomeIconOffset") as? JSONObject)?.let { offset ->
            val x = (offset.opt("x") as? Number)?.toDouble()
            val y = (offset.opt("y") as? Number)?.toDouble()
            if (x != null && y != null && x in -1000.0..1000.0 && y in -1000.0..1000.0) {
                style.welcomeIconOffset = DpOffset(x.dp, y.dp)
            }
        }
        text("closeImage")?.let { name ->
            val image = ReceptionAssets.image(context, name)
            if (image != null) {
                style.closeImage = image
            } else {
                keepPrevious("closeImage", "Missing close image ignored")
                style.closeImage = Reception.appearance.closeImage
            }
        }
        (values.opt("welcomeIcon") as? JSONObject)?.let { icon ->
            val symbol = icon.opt("symbol") as? String
            val image = (icon.opt("image") as? String)?.let { ReceptionAssets.image(context, it) }
            when {
                icon.opt("hidden") == true -> style.welcomeIcon = Reception.WelcomeIcon.hidden
                symbol != null -> style.welcomeIcon = Reception.WelcomeIcon.symbol(symbol)
                image != null -> style.welcomeIcon = Reception.WelcomeIcon.image(image)
                else -> {
                    keepPrevious("welcomeIcon", "Missing welcome icon ignored")
                    style.welcomeIcon = Reception.appearance.welcomeIcon
                }
            }
        }
        this.values = accepted
        Reception.appearance = style
    }

    private fun closeIconName(icon: Reception.CloseIcon): String = when (icon) {
        Reception.CloseIcon.XMARK -> "xmark"
        Reception.CloseIcon.CHEVRON_DOWN -> "chevron.down"
        Reception.CloseIcon.ARROW_DOWN -> "arrow.down"
    }

    /** A JSON value as Kotlin strings and maps, as [ReceptionColor.decode] reads it. */
    private fun plain(value: Any?): Any? = if (value is JSONObject) value.keys().asSequence().associateWith { value.opt(it) } else value

    private const val TAG = "ReceptionFlutter"
}
