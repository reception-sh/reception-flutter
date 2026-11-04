package sh.reception.flutter

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions
import androidx.core.app.ActivityCompat
import androidx.core.app.ActivityOptionsCompat
import io.flutter.plugin.common.PluginRegistry
import java.lang.ref.WeakReference

/**
 * Activity results for the embedded chat (photo picker, notification permission) when the Flutter activity is a plain
 * `FlutterActivity`, which has no `ActivityResultRegistry`. Launches go through the activity; results come back
 * through the plugin binding's listeners. A `FlutterFragmentActivity` brings its own registry and needs none of this.
 */
internal class ActivityResults(activity: Activity) :
    ActivityResultRegistry(), PluginRegistry.ActivityResultListener, PluginRegistry.RequestPermissionsResultListener {
    private val activity = WeakReference(activity)
    private val main = Handler(Looper.getMainLooper())

    override fun <I, O> onLaunch(requestCode: Int, contract: ActivityResultContract<I, O>, input: I, options: ActivityOptionsCompat?) {
        val activity = activity.get() ?: return cancel(requestCode)
        contract.getSynchronousResult(activity, input)?.let { result ->
            main.post { dispatchResult(requestCode, result.value) }
            return
        }
        val intent = contract.createIntent(activity, input)
        if (intent.action == RequestMultiplePermissions.ACTION_REQUEST_PERMISSIONS) {
            val permissions = intent.getStringArrayExtra(RequestMultiplePermissions.EXTRA_PERMISSIONS) ?: emptyArray()
            ActivityCompat.requestPermissions(activity, permissions, requestCode)
            return
        }
        try {
            activity.startActivityForResult(intent, requestCode, options?.toBundle())
        } catch (_: ActivityNotFoundException) {
            cancel(requestCode)
        }
    }

    private fun cancel(requestCode: Int) {
        main.post { dispatchResult(requestCode, Activity.RESULT_CANCELED, null) }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean =
        dispatchResult(requestCode, resultCode, data)

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean =
        dispatchResult(
            requestCode, Activity.RESULT_OK,
            Intent().putExtra(RequestMultiplePermissions.EXTRA_PERMISSIONS, permissions)
                .putExtra(RequestMultiplePermissions.EXTRA_PERMISSION_GRANT_RESULTS, grantResults),
        )

    /** The context the embedded chat composes in: the activity's, with this registry. */
    class OwnerContext(base: Context, override val activityResultRegistry: ActivityResultRegistry) :
        ContextWrapper(base), ActivityResultRegistryOwner
}
