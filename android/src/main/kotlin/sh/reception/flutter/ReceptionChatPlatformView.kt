package sh.reception.flutter

import android.app.Activity
import android.content.Context
import android.content.MutableContextWrapper
import android.os.Bundle
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.compose.runtime.Recomposer
import androidx.compose.ui.platform.AndroidUiDispatcher
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.core.os.BundleCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import sh.reception.ReceptionChatView
import java.lang.ref.WeakReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * The activity side of the engine's embedded chats. Flutter keeps platform views when a cached engine outlives its
 * activity (recreation after a configuration change, or a new activity for the same engine), so every live chat is
 * moved to the activity the plugin is attached to now, and none keeps a destroyed one. Main thread only.
 */
internal class ChatActivity {
    val results = ActivityResults()
    private val views = LinkedHashSet<ReceptionChatPlatformView>()
    private var binding: ActivityPluginBinding? = null
    private var reference: WeakReference<Activity>? = null
    private var attachments = 0

    /** Saved states of the chats shown when the process died, handed to the chats Dart creates again, in order. */
    private val restoredStates = ArrayDeque<Bundle>()

    val activity: Activity? get() = reference?.get()

    private val saveState = object : ActivityPluginBinding.OnSaveInstanceStateListener {
        override fun onSaveInstanceState(bundle: Bundle) {
            bundle.putBundle(RESULTS, results.save())
            bundle.putParcelableArrayList(VIEWS, ArrayList(views.map { it.saveState() }))
        }

        override fun onRestoreInstanceState(bundle: Bundle?) {
            // Only a plugin that just started restores: a retained one already holds this state.
            if (bundle == null || attachments != 1 || views.isNotEmpty()) return
            bundle.getBundle(RESULTS)?.let(results::restore)
            BundleCompat.getParcelableArrayList(bundle, VIEWS, Bundle::class.java)?.let(restoredStates::addAll)
        }
    }

    fun attach(binding: ActivityPluginBinding) {
        detach()
        attachments += 1
        this.binding = binding
        reference = WeakReference(binding.activity)
        results.attach(binding.activity)
        binding.addActivityResultListener(results)
        binding.addRequestPermissionsResultListener(results)
        binding.addOnSaveStateListener(saveState)
        views.forEach { it.attach(binding.activity) }
    }

    fun detach() {
        binding?.let {
            it.removeActivityResultListener(results)
            it.removeRequestPermissionsResultListener(results)
            it.removeOnSaveStateListener(saveState)
        }
        binding = null
        reference = null
        results.detach()
        views.forEach { it.detach() }
    }

    fun add(view: ReceptionChatPlatformView): Bundle? {
        views.add(view)
        return restoredStates.removeFirstOrNull()
    }

    fun remove(view: ReceptionChatPlatformView) {
        views.remove(view)
    }

    private companion object {
        const val RESULTS = "sh.reception.flutter.results"
        const val VIEWS = "sh.reception.flutter.chatViews"
    }
}

/** Creates the embedded chat for `ReceptionChatView` widgets (viewType `reception_flutter/chat`). */
internal class ReceptionChatViewFactory(private val chats: ChatActivity) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView = ReceptionChatPlatformView(context, chats)

    companion object {
        const val VIEW_TYPE = "reception_flutter/chat"
    }
}

/**
 * Hosts the SDK's chat View. Its composition follows the lifecycle of the activity the plugin is attached to, as an
 * embedded chat in a native screen does, moves with the engine to a new activity, and ends only when Flutter disposes
 * the view. It runs on its own recomposer: Compose would otherwise look for the window's recomposer on the window's
 * content view, Flutter's view, which carries no lifecycle owner.
 */
internal class ReceptionChatPlatformView(flutterContext: Context, private val chats: ChatActivity) : PlatformView {
    private val context = ChatContext(chats.activity ?: flutterContext, chats.results)
    private val owner = ViewOwner(chats.add(this))
    private val scope = CoroutineScope(AndroidUiDispatcher.Main)
    private val recomposer = Recomposer(scope.coroutineContext)
    private val container = OverlapInsets(context).apply {
        setViewTreeLifecycleOwner(owner)
        setViewTreeSavedStateRegistryOwner(owner)
        addView(ReceptionChatView(context).also {
            it.setParentCompositionContext(recomposer)
            // Flutter moves the view to the new activity's window; the chat's state stays.
            it.setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnLifecycleDestroyed(owner))
        })
    }

    init {
        scope.launch { recomposer.runRecomposeAndApplyChanges() }
        attach(chats.activity)
    }

    fun attach(activity: Activity?) {
        if (activity != null) context.setBaseContext(activity)
        owner.follow((activity as? LifecycleOwner)?.lifecycle, attached = activity != null)
    }

    /** Stopped until an activity is attached again; the destroyed activity is let go. */
    fun detach() {
        owner.follow(null, attached = false)
        context.setBaseContext(context.applicationContext)
    }

    fun saveState(): Bundle = owner.save()

    override fun getView() = container

    override fun dispose() {
        chats.remove(this)
        container.removeAllViews()
        recomposer.cancel()
        scope.cancel()
        owner.destroy()
    }

    /** The context the chat composes in: the current activity's, with the plugin's result registry. */
    private class ChatContext(base: Context, override val activityResultRegistry: ActivityResultRegistry) :
        MutableContextWrapper(base), ActivityResultRegistryOwner

    /**
     * The lifecycle and saved state Compose needs. The lifecycle mirrors the current activity's but never reaches
     * DESTROYED with it: an activity destroyed under a cached engine only stops the chat until the next one attaches.
     */
    private class ViewOwner(restored: Bundle?) : SavedStateRegistryOwner {
        private val registry = LifecycleRegistry(this)
        private val savedState = SavedStateRegistryController.create(this)
        private var parent: Lifecycle? = null
        private val observer = LifecycleEventObserver { _, event ->
            registry.currentState = event.targetState.coerceAtLeast(Lifecycle.State.CREATED)
        }
        override val lifecycle: Lifecycle get() = registry
        override val savedStateRegistry: SavedStateRegistry get() = savedState.savedStateRegistry

        init {
            savedState.performRestore(restored)
        }

        fun follow(lifecycle: Lifecycle?, attached: Boolean) {
            if (registry.currentState == Lifecycle.State.DESTROYED) return
            parent?.removeObserver(observer)
            parent = lifecycle
            when {
                lifecycle != null -> lifecycle.addObserver(observer)
                attached -> registry.currentState = Lifecycle.State.RESUMED
                else -> registry.currentState = Lifecycle.State.CREATED
            }
        }

        fun save(): Bundle = Bundle().also(savedState::performSave)

        fun destroy() {
            parent?.removeObserver(observer)
            parent = null
            if (registry.currentState.isAtLeast(Lifecycle.State.CREATED)) registry.currentState = Lifecycle.State.DESTROYED
        }
    }
}
