package sh.reception.flutter

import androidx.activity.result.ActivityResultRegistryOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import sh.reception.Reception
import sh.reception.ReceptionInternalApi

/**
 * Registers the host API and the chat view, and hands the Flutter activity to the SDK: Dart configures after that
 * activity resumed, so the SDK would otherwise have no activity to present the chat over until the next resume.
 * Push delivery needs nothing here: [ReceptionPushReceiver] shows replies and the SDK's notification activity routes
 * taps.
 */
public class ReceptionFlutterPlugin : FlutterPlugin, ActivityAware {
    private var host: ReceptionHost? = null
    private var binding: ActivityPluginBinding? = null
    private var attachment: ReceptionChatViewFactory.Attachment? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val host = ReceptionHost(binding.applicationContext, ReceptionFlutterApi(binding.binaryMessenger))
        ReceptionHostApi.setUp(binding.binaryMessenger, host)
        binding.platformViewRegistry.registerViewFactory(ReceptionChatViewFactory.VIEW_TYPE, ReceptionChatViewFactory { attachment })
        this.host = host
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ReceptionHostApi.setUp(binding.binaryMessenger, null)
        host?.invalidate()
        host = null
    }

    @OptIn(ReceptionInternalApi::class)
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        val activity = binding.activity
        Reception.noteCurrentActivity(activity)
        val results = if (activity is ActivityResultRegistryOwner) null else ActivityResults(activity)
        results?.let {
            binding.addActivityResultListener(it)
            binding.addRequestPermissionsResultListener(it)
        }
        this.binding = binding
        attachment = ReceptionChatViewFactory.Attachment(activity, results)
    }

    override fun onDetachedFromActivity() {
        attachment?.results?.let {
            binding?.removeActivityResultListener(it)
            binding?.removeRequestPermissionsResultListener(it)
        }
        binding = null
        attachment = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
}
