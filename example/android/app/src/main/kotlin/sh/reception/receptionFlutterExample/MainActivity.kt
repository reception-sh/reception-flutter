package sh.reception.receptionFlutterExample

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Asks for notification permission for the example's Enable notifications button, like the iOS AppDelegate. */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "reception_example/notifications")
            .setMethodCallHandler { call, result ->
                if (call.method != "requestPermission") return@setMethodCallHandler result.notImplemented()
                if (Build.VERSION.SDK_INT < 33) return@setMethodCallHandler result.success(true)
                pending = result
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST)
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST) return
        pending?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        pending = null
    }

    private companion object {
        const val REQUEST = 7301
    }
}
