package sh.reception.flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReceptionColorTest {
    @Test
    fun decodesHexAsArgb() {
        assertEquals(ReceptionColor(0xFF8A2BE2.toInt(), 0xFF8A2BE2.toInt()), ReceptionColor.decode("#8A2BE2"))
        assertEquals(ReceptionColor(0x80112233.toInt(), 0x80112233.toInt()), ReceptionColor.decode("#11223380"))
    }

    @Test
    fun decodesLightDarkPairs() {
        assertEquals(
            ReceptionColor(0xFFFFFFFF.toInt(), 0xFF000000.toInt()),
            ReceptionColor.decode(mapOf("light" to "#ffffff", "dark" to "#000000")),
        )
    }

    @Test
    fun rejectsMalformedValues() {
        for (value in listOf("8A2BE2", "#8A2BE", "#GGGGGG", "#11223344a", 0xFF, null)) assertNull(ReceptionColor.decode(value))
        assertNull(ReceptionColor.decode(mapOf("light" to "#ffffff")))
        assertNull(ReceptionColor.decode(mapOf("light" to "#ffffff", "dark" to "black")))
        assertNull(ReceptionColor.decode(mapOf("light" to "#ffffff", "dark" to "#000000", "extra" to "#000000")))
    }
}
