package sh.reception.flutter

import android.app.Activity
import android.content.Context
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.compose.runtime.Recomposer
import androidx.compose.ui.platform.AndroidUiDispatcher
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import sh.reception.ReceptionChatView
import java.lang.ref.WeakReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/** Creates the embedded chat for `ReceptionChatView` widgets (viewType `reception_flutter/chat`). */
internal class ReceptionChatViewFactory(private val attachment: () -> Attachment?) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    /** The activity the plugin is attached to (held weakly) and, for a plain `FlutterActivity`, its result bridge. */
    class Attachment(activity: Activity, val results: ActivityResults?) {
        private val reference = WeakReference(activity)
        val activity: Activity? get() = reference.get()
    }

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ReceptionChatPlatformView(context, attachment())

    companion object {
        const val VIEW_TYPE = "reception_flutter/chat"
    }
}

/**
 * Hosts the SDK's chat View. Its composition follows the activity's lifecycle, as an embedded chat in a native screen
 * does, and ends when Flutter disposes the view. It runs on its own recomposer: Compose would otherwise look for the
 * window's recomposer on the window's content view, Flutter's view, which carries no lifecycle owner.
 */
internal class ReceptionChatPlatformView(context: Context, attachment: ReceptionChatViewFactory.Attachment?) : PlatformView {
    private val owner = ViewOwner((attachment?.activity as? LifecycleOwner)?.lifecycle)
    private val scope = CoroutineScope(AndroidUiDispatcher.Main)
    private val recomposer = Recomposer(scope.coroutineContext)
    private val container = OverlapInsets(context).apply {
        setViewTreeLifecycleOwner(owner)
        setViewTreeSavedStateRegistryOwner(owner)
        val results = attachment?.results
        val chatContext = if (results != null && context !is ActivityResultRegistryOwner) {
            ActivityResults.OwnerContext(context, results)
        } else {
            context
        }
        addView(ReceptionChatView(chatContext).also { it.setParentCompositionContext(recomposer) })
    }

    init {
        scope.launch { recomposer.runRecomposeAndApplyChanges() }
    }

    override fun getView() = container

    override fun dispose() {
        container.removeAllViews()
        recomposer.cancel()
        scope.cancel()
        owner.destroy()
    }

    /** The lifecycle and saved state Compose needs, mirroring the activity's lifecycle (resumed without one). */
    private class ViewOwner(private val parent: Lifecycle?) : SavedStateRegistryOwner {
        private val registry = LifecycleRegistry(this)
        private val savedState = SavedStateRegistryController.create(this)
        private val observer = LifecycleEventObserver { _, event -> registry.handleLifecycleEvent(event) }
        override val lifecycle: Lifecycle get() = registry
        override val savedStateRegistry: SavedStateRegistry get() = savedState.savedStateRegistry

        init {
            savedState.performRestore(null)
            if (parent != null) parent.addObserver(observer) else registry.currentState = Lifecycle.State.RESUMED
        }

        fun destroy() {
            parent?.removeObserver(observer)
            if (registry.currentState.isAtLeast(Lifecycle.State.CREATED)) registry.currentState = Lifecycle.State.DESTROYED
        }
    }
}
