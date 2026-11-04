package sh.reception.flutter

import android.annotation.SuppressLint
import android.content.Context
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.core.content.res.ResourcesCompat
import androidx.core.graphics.drawable.toBitmap
import io.flutter.FlutterInjector
import org.json.JSONArray
import org.json.JSONException
import java.io.IOException

/** Fonts and images of the host app, named in Dart's appearance. */
internal object ReceptionAssets {
    /** A font of the app's `pubspec.yaml` with its declared weights and styles. */
    data class FontAsset(val path: String, val weight: Int, val italic: Boolean)

    /** A font family declared in the app's `pubspec.yaml` (Flutter's `FontManifest.json`), or null. */
    fun fontFamily(context: Context, family: String): FontFamily? {
        val loader = FlutterInjector.instance().flutterLoader()
        val manifest = try {
            context.assets.open(loader.getLookupKeyForAsset("FontManifest.json")).bufferedReader().use { it.readText() }
        } catch (_: IOException) {
            return null
        }
        val fonts = fontAssets(manifest, family).ifEmpty { return null }
        return FontFamily(fonts.map {
            Font(loader.getLookupKeyForAsset(it.path), context.assets, FontWeight(it.weight),
                if (it.italic) FontStyle.Italic else FontStyle.Normal)
        })
    }

    /** The fonts of [family] in a `FontManifest.json`; weights outside 1–1000 count as regular. */
    fun fontAssets(manifest: String, family: String): List<FontAsset> = try {
        val families = JSONArray(manifest)
        (0 until families.length()).map { families.getJSONObject(it) }
            .filter { it.optString("family") == family }
            .flatMap { entry ->
                val fonts = entry.optJSONArray("fonts") ?: JSONArray()
                (0 until fonts.length()).map { fonts.getJSONObject(it) }.mapNotNull { font ->
                    val path = font.optString("asset").takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                    FontAsset(path, font.optInt("weight", 400).takeIf { it in 1..1000 } ?: 400, font.optString("style") == "italic")
                }
            }
    } catch (_: JSONException) {
        emptyList()
    }

    /** A drawable resource of the app by name, drawn at its intrinsic size; null when missing. */
    @SuppressLint("DiscouragedApi") // Dart passes the name; there is no generated R field to reference.
    fun image(context: Context, name: String): Painter? {
        val id = context.resources.getIdentifier(name, "drawable", context.packageName).takeIf { it != 0 } ?: return null
        return try {
            val drawable = ResourcesCompat.getDrawable(context.resources, id, context.theme) ?: return null
            BitmapPainter(drawable.toBitmap().asImageBitmap())
        } catch (_: IllegalArgumentException) {
            // A drawable without an intrinsic size, such as a plain color.
            null
        }
    }
}
