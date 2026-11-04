package sh.reception.flutter

import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.snapshots.Snapshot
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Sends Compose's global snapshot apply notifications after SDK state writes, so `snapshotFlow` sees changes to
 * Compose state (such as `availablePaywalls`) while no Compose UI runs: only a composition's recomposer sends them
 * otherwise. `start` runs on the main thread.
 */
internal object SnapshotNotifications {
    private val main = Handler(Looper.getMainLooper())
    private var started = false
    /** Writes can happen on any thread; one notification is queued at a time. */
    private val scheduled = AtomicBoolean(false)

    fun start() {
        if (started) return
        started = true
        Snapshot.registerGlobalWriteObserver {
            if (!scheduled.compareAndSet(false, true)) return@registerGlobalWriteObserver
            main.post {
                scheduled.set(false)
                Snapshot.sendApplyNotifications()
            }
        }
    }
}
