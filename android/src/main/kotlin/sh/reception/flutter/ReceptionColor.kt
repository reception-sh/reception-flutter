package sh.reception.flutter

/** A color from Dart's appearance JSON: one hex string, or a `{light, dark}` pair of them. */
internal data class ReceptionColor(val light: Int, val dark: Int) {
    /** The SDK color, which picks the variant of the mode the chat draws in. */
    val sdk: sh.reception.ReceptionColor get() = sh.reception.ReceptionColor.argb(light, dark)

    companion object {
        private val hex = Regex("^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$")

        fun decode(value: Any?): ReceptionColor? {
            if (value is String) return decodeHex(value)?.let { ReceptionColor(it, it) }
            if (value !is Map<*, *> || value.size != 2) return null
            val light = (value["light"] as? String)?.let(::decodeHex) ?: return null
            val dark = (value["dark"] as? String)?.let(::decodeHex) ?: return null
            return ReceptionColor(light, dark)
        }

        /** `#RRGGBB` or `#RRGGBBAA` as an ARGB color int. */
        private fun decodeHex(text: String): Int? {
            if (!hex.matches(text)) return null
            val value = text.substring(1).toLong(16)
            val rgba = if (text.length == 7) (value shl 8) or 0xFF else value
            return ((rgba and 0xFF) shl 24 or (rgba ushr 8)).toInt()
        }
    }
}
