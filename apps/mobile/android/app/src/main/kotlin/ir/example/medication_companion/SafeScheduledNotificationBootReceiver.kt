package ir.example.medication_companion

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver

/** Sole manifest-registered boot rescheduler. Never replay stale alarms while
 * restore or its mandatory reconciliation is pending or storage is locked.
 * The plugin class remains available but must not itself be a receiver entry.
 */
class SafeScheduledNotificationBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!NativeBackupStartupGate.isSafeForDatabaseOrBoot(context)) return
        ScheduledNotificationBootReceiver().onReceive(context, intent)
    }
}
