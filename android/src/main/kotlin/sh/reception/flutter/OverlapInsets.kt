package sh.reception.flutter

import android.content.Context
import android.os.Build
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsAnimation
import android.widget.FrameLayout
import androidx.annotation.RequiresApi
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import kotlin.math.max

/**
 * Holds the embedded chat and hands it only the part of each window inset (keyboard, system bars, cutout) that
 * overlaps this view, as iOS does for a view that avoids the keyboard. Flutter already lays the view out above the
 * keyboard when the screen resizes for it (`Scaffold.resizeToAvoidBottomInset`); the full window inset would then
 * pad the chat a second time.
 */
internal class OverlapInsets(context: Context) : FrameLayout(context) {
    private val location = IntArray(2)

    override fun dispatchApplyWindowInsets(insets: WindowInsets): WindowInsets {
        val adjusted = overlapping(WindowInsetsCompat.toWindowInsetsCompat(insets, this)).toWindowInsets() ?: insets
        for (index in 0 until childCount) getChildAt(index).dispatchApplyWindowInsets(adjusted)
        return insets
    }

    @RequiresApi(Build.VERSION_CODES.R)
    override fun dispatchWindowInsetsAnimationProgress(
        insets: WindowInsets,
        runningAnimations: MutableList<WindowInsetsAnimation>,
    ): WindowInsets {
        val adjusted = overlapping(WindowInsetsCompat.toWindowInsetsCompat(insets, this)).toWindowInsets() ?: insets
        for (index in 0 until childCount) getChildAt(index).dispatchWindowInsetsAnimationProgress(adjusted, runningAnimations)
        return insets
    }

    /** Flutter moves and resizes the view without new window insets, so the overlap is measured again. */
    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        ViewCompat.getRootWindowInsets(this)?.toWindowInsets()?.let(::dispatchApplyWindowInsets)
    }

    private fun overlapping(insets: WindowInsetsCompat): WindowInsetsCompat {
        val root: View = rootView
        getLocationInWindow(location)
        val left = location[0]
        val top = location[1]
        val right = root.width - left - width
        val bottom = root.height - top - height
        val builder = WindowInsetsCompat.Builder(insets)
        for (type in types) {
            val inset = insets.getInsets(type)
            builder.setInsets(
                type,
                Insets.of(max(0, inset.left - left), max(0, inset.top - top), max(0, inset.right - right), max(0, inset.bottom - bottom)),
            )
        }
        return builder.build()
    }

    private companion object {
        val types = listOf(
            WindowInsetsCompat.Type.ime(), WindowInsetsCompat.Type.statusBars(), WindowInsetsCompat.Type.navigationBars(),
            WindowInsetsCompat.Type.captionBar(), WindowInsetsCompat.Type.displayCutout(),
            WindowInsetsCompat.Type.systemGestures(), WindowInsetsCompat.Type.mandatorySystemGestures(),
            WindowInsetsCompat.Type.tappableElement(),
        )
    }
}
