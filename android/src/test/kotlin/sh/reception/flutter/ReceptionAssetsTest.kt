package sh.reception.flutter

import org.junit.Assert.assertEquals
import org.junit.Test

class ReceptionAssetsTest {
    private val manifest = """
        [{"family":"MaterialIcons","fonts":[{"asset":"fonts/MaterialIcons-Regular.otf"}]},
         {"family":"Inter","fonts":[{"asset":"fonts/Inter-Regular.ttf"},{"asset":"fonts/Inter-Bold.ttf","weight":700},
          {"asset":"fonts/Inter-Italic.ttf","style":"italic"},{"asset":"fonts/Odd.ttf","weight":5000},{"weight":300}]},
         {"family":"packages/brand/Brand","fonts":[{"asset":"packages/brand/fonts/Brand.ttf"}]}]
    """.trimIndent()

    @Test
    fun readsTheFamilysFontsWithWeightAndStyle() {
        assertEquals(
            listOf(
                ReceptionAssets.FontAsset("fonts/Inter-Regular.ttf", 400, false),
                ReceptionAssets.FontAsset("fonts/Inter-Bold.ttf", 700, false),
                ReceptionAssets.FontAsset("fonts/Inter-Italic.ttf", 400, true),
                ReceptionAssets.FontAsset("fonts/Odd.ttf", 400, false),
            ),
            ReceptionAssets.fontAssets(manifest, "Inter"),
        )
        assertEquals(
            listOf(ReceptionAssets.FontAsset("packages/brand/fonts/Brand.ttf", 400, false)),
            ReceptionAssets.fontAssets(manifest, "packages/brand/Brand"),
        )
    }

    @Test
    fun unknownFamiliesAndMalformedManifestsHaveNoFonts() {
        assertEquals(emptyList<ReceptionAssets.FontAsset>(), ReceptionAssets.fontAssets(manifest, "Missing"))
        assertEquals(emptyList<ReceptionAssets.FontAsset>(), ReceptionAssets.fontAssets("{", "Inter"))
    }
}
