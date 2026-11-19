package ir.example.medication_companion

import android.content.ContentProvider
import android.content.ContentValues
import android.content.pm.ApplicationInfo
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.os.Process
import android.os.Binder

/** Debug-only, CLI-controlled, separate Android process used ONLY for the
 * synthetic D3d process-kill matrix. It does not open production databases.
 */
class NativeRestoreKillProbeProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle? {
        val ctx = context ?: throw IllegalStateException("provider has no context")
        if ((ctx.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0 ||
            (Binder.getCallingUid() != Process.myUid() &&
                Binder.getCallingUid() != Process.SHELL_UID)) {
            throw SecurityException("debug-only local recovery probe")
        }
        return when (method) {
            "pid" -> Bundle().apply { putInt("pid", Process.myPid()) }
            // D4b-2: a second Android process attempts only the shared admission
            // lease. It never opens SQLite or changes any user data.
            "probeAcquireSession" -> {
                val token = NativeBackupStartupGate.acquireDatabaseSession(ctx)
                val released = token != null &&
                    NativeBackupStartupGate.releaseDatabaseSession(token)
                Bundle().apply {
                    putInt("pid", Process.myPid())
                    putBoolean("admitted", token != null && released)
                }
            }
            "kill_OLD_SAVED", "kill_NEW_INSTALLED" -> {
                val id = arg ?: throw IllegalArgumentException("missing probe ID")
                val state = method.removePrefix("kill_")
                NativeRestoreFaultMatrix.prepareProcessDeathSandbox(ctx, id, state)
                // Nothing in the caller's process dies. This kills only the
                // isolated :m4killprobe process after durable disk writes.
                Process.killProcess(Process.myPid())
                throw IllegalStateException("OS refused to kill isolated probe")
            }
            "recover_OLD_SAVED", "recover_NEW_INSTALLED" -> {
                val id = arg ?: throw IllegalArgumentException("missing probe ID")
                val state = method.removePrefix("recover_")
                val terminal = NativeRestoreFaultMatrix.recoverProcessDeathSandbox(ctx, id, state)
                Bundle().apply {
                    putInt("pid", Process.myPid())
                    putBoolean("ok", true)
                    putString("terminal", terminal)
                }
            }
            "cleanup" -> {
                val id = arg ?: throw IllegalArgumentException("missing probe ID")
                NativeRestoreFaultMatrix.cleanupCompletedProcessDeathSandbox(ctx, id)
                Bundle().apply { putBoolean("ok", true) }
            }
            else -> throw IllegalArgumentException("unsupported debug probe operation")
        }
    }

    override fun query(
        uri: Uri, projection: Array<String>?, selection: String?,
        selectionArgs: Array<String>?, sortOrder: String?
    ): Cursor? = throw UnsupportedOperationException()
    override fun getType(uri: Uri): String? = throw UnsupportedOperationException()
    override fun insert(uri: Uri, values: ContentValues?): Uri? =
        throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?): Int =
        throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?,
        selectionArgs: Array<String>?): Int = throw UnsupportedOperationException()
}
