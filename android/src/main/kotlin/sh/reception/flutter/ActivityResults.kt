package sh.reception.flutter

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.activity.result.ActivityResult
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions
import androidx.activity.result.contract.ActivityResultContracts.StartActivityForResult
import androidx.core.app.ActivityCompat
import androidx.core.app.ActivityOptionsCompat
import io.flutter.plugin.common.PluginRegistry
import java.lang.ref.WeakReference

/**
 * The activity result registry of every embedded chat (photo picker, notification permission). The plugin keeps one
 * for its engine, so a chat that survives its activity (a cached engine) keeps its launchers when the activity is
 * recreated, and its state goes into the activity's saved state, so a result that arrives after the process died still
 * finds the launcher key the chat restores.
 *
 * Launches go through the activity the plugin is attached to: through its own registry when it has one
 * (`FlutterFragmentActivity`), under a key that the next activity registers again and so receives the result the old
 * one saved; otherwise (`FlutterActivity`) with a request code, whose result comes back through the plugin binding's
 * listeners. Main thread only.
 */
internal class ActivityResults :
    ActivityResultRegistry(), PluginRegistry.ActivityResultListener, PluginRegistry.RequestPermissionsResultListener {
    private var activity: WeakReference<Activity>? = null
    private val main = Handler(Looper.getMainLooper())

    /** Request codes launched through an activity's registry that have no result yet, with whether they asked for
     *  permissions. */
    private val forwarded = LinkedHashMap<Int, Boolean>()
    private val launchers = mutableMapOf<Int, ActivityResultLauncher<*>>()
    private var owner: ActivityResultRegistry? = null

    /** The activity launches go through; pending forwarded launches are registered with its registry again. */
    fun attach(activity: Activity) {
        detach()
        this.activity = WeakReference(activity)
        val registry = (activity as? ActivityResultRegistryOwner)?.activityResultRegistry ?: return
        owner = registry
        for ((requestCode, permissions) in forwarded.entries.toList()) register(registry, requestCode, permissions)
    }

    fun detach() {
        // The activity saved its registry's state before it was destroyed, so the next one restores pending results.
        launchers.values.forEach { it.unregister() }
        launchers.clear()
        owner = null
        activity = null
    }

    fun save(): Bundle = Bundle().also {
        onSaveInstanceState(it)
        it.putIntArray(FORWARDED_CODES, forwarded.keys.toIntArray())
        it.putBooleanArray(FORWARDED_PERMISSIONS, forwarded.values.toBooleanArray())
    }

    /** Before any chat registers a launcher: after the process died, with the state [save] put in the activity's. */
    fun restore(state: Bundle) {
        onRestoreInstanceState(state)
        val codes = state.getIntArray(FORWARDED_CODES) ?: return
        val permissions = state.getBooleanArray(FORWARDED_PERMISSIONS) ?: return
        if (codes.size != permissions.size) return
        codes.indices.forEach { forwarded[codes[it]] = permissions[it] }
        owner?.let { registry -> forwarded.forEach { (code, permission) -> register(registry, code, permission) } }
    }

    override fun <I, O> onLaunch(requestCode: Int, contract: ActivityResultContract<I, O>, input: I, options: ActivityOptionsCompat?) {
        val activity = activity?.get() ?: return cancel(requestCode)
        contract.getSynchronousResult(activity, input)?.let { result ->
            main.post { dispatchResult(requestCode, result.value) }
            return
        }
        val intent = contract.createIntent(activity, input)
        val permissions = intent.action == RequestMultiplePermissions.ACTION_REQUEST_PERMISSIONS
        val names = intent.getStringArrayExtra(RequestMultiplePermissions.EXTRA_PERMISSIONS) ?: emptyArray()
        owner?.let { registry ->
            forwarded[requestCode] = permissions
            try {
                @Suppress("UNCHECKED_CAST")
                if (permissions) {
                    (register(registry, requestCode, true) as ActivityResultLauncher<Array<String>>).launch(names, options)
                } else {
                    (register(registry, requestCode, false) as ActivityResultLauncher<Intent>).launch(intent, options)
                }
            } catch (_: ActivityNotFoundException) {
                finish(requestCode)
                cancel(requestCode)
            }
            return
        }
        if (permissions) {
            ActivityCompat.requestPermissions(activity, names, requestCode)
            return
        }
        try {
            activity.startActivityForResult(intent, requestCode, options?.toBundle())
        } catch (_: ActivityNotFoundException) {
            cancel(requestCode)
        }
    }

    /** A launcher on the activity's registry whose result goes to this registry's [requestCode]. */
    private fun register(registry: ActivityResultRegistry, requestCode: Int, permissions: Boolean): ActivityResultLauncher<*> {
        launchers[requestCode]?.let { return it }
        val launcher = if (permissions) {
            registry.register("$KEY_PREFIX.permissions:$requestCode", RequestMultiplePermissions()) { grants ->
                finish(requestCode)
                val names = grants.keys.toTypedArray()
                val results = grants.values.map { if (it) PackageManager.PERMISSION_GRANTED else PackageManager.PERMISSION_DENIED }
                dispatchResult(requestCode, Activity.RESULT_OK, permissionResult(names, results.toIntArray()))
            }
        } else {
            registry.register("$KEY_PREFIX.activity:$requestCode", StartActivityForResult()) { result: ActivityResult ->
                finish(requestCode)
                dispatchResult(requestCode, result.resultCode, result.data)
            }
        }
        launchers[requestCode] = launcher
        return launcher
    }

    private fun finish(requestCode: Int) {
        forwarded.remove(requestCode)
        launchers.remove(requestCode)?.unregister()
    }

    private fun cancel(requestCode: Int) {
        main.post { dispatchResult(requestCode, Activity.RESULT_CANCELED, null) }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean =
        requestCode !in forwarded && dispatchResult(requestCode, resultCode, data)

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean =
        requestCode !in forwarded && dispatchResult(requestCode, Activity.RESULT_OK, permissionResult(permissions, grantResults))

    private fun permissionResult(permissions: Array<out String>, grantResults: IntArray) =
        Intent().putExtra(RequestMultiplePermissions.EXTRA_PERMISSIONS, permissions)
            .putExtra(RequestMultiplePermissions.EXTRA_PERMISSION_GRANT_RESULTS, grantResults)

    private companion object {
        const val KEY_PREFIX = "sh.reception.flutter"
        const val FORWARDED_CODES = "$KEY_PREFIX.forwardedCodes"
        const val FORWARDED_PERMISSIONS = "$KEY_PREFIX.forwardedPermissions"
    }
}
