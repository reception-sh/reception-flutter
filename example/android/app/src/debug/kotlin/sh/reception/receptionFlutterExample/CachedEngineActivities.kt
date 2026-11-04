package sh.reception.receptionFlutterExample

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Debug-only hosts for verification/android.md "Fix round 1": a cached engine that outlives its activity, which these
 * activities let Android recreate on rotation (no `configChanges`). Start them with
 * `adb shell am start -n sh.reception.receptionFlutterExample/.CachedEngineActivity` (or `.CachedEngineFragmentActivity`).
 */
private fun cachedEngine(context: Context, id: String): FlutterEngine =
    FlutterEngineCache.getInstance().get(id) ?: FlutterEngine(context.applicationContext).also {
        it.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(id, it)
    }

class CachedEngineActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine = cachedEngine(context, "activity")

    override fun shouldDestroyEngineWithHost(): Boolean = false
}

class CachedEngineFragmentActivity : FlutterFragmentActivity() {
    // A provided engine would be destroyed with the fragment (FlutterFragment.withNewEngine always asks for that), so
    // the fragment gets the cached engine by its ID.
    override fun getCachedEngineId(): String {
        cachedEngine(this, "fragmentActivity")
        return "fragmentActivity"
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false
}
