package sh.reception.flutter

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import sh.reception.Reception
import sh.reception.ReceptionInternalApi

/**
 * Registers the host API and the chat view, and hands the Flutter activity to the SDK: Dart configures after that
 * activity resumed, so the SDK would otherwise have no activity to present the chat over until the next resume.
 * Embedded chats move with the engine from activity to activity ([ChatActivity]). Push delivery needs nothing here:
 * [ReceptionPushReceiver] shows replies and the SDK's notification activity routes taps.
 */
public class ReceptionFlutterPlugin : FlutterPlugin, ActivityAware {
    private var host: ReceptionHost? = null
    private val chats = ChatActivity()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val host = ReceptionHost(binding.applicationContext, ReceptionFlutterApi(binding.binaryMessenger))
        ReceptionHostApi.setUp(binding.binaryMessenger, host)
        binding.platformViewRegistry.registerViewFactory(ReceptionChatViewFactory.VIEW_TYPE, ReceptionChatViewFactory(chats))
        this.host = host
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ReceptionHostApi.setUp(binding.binaryMessenger, null)
        host?.invalidate()
        host = null
    }

    @OptIn(ReceptionInternalApi::class)
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        Reception.noteCurrentActivity(binding.activity)
        chats.attach(binding)
    }

    override fun onDetachedFromActivity() = chats.detach()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = chats.detach()
}
