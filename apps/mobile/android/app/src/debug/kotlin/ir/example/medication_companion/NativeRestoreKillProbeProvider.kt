package ir.example.medication_companion

import android.content.ContentProvider
import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
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
    // Only a random debug fixture directory can be named by this kill probe.
    private fun ownerDeathFixture(ctx: Context, suppliedId: String?): File {
        val id = UUID.fromString(suppliedId ?: throw IllegalArgumentException("missing probe ID"))
        require(suppliedId == id.toString()) { "noncanonical fixture ID" }
        val noBackup = ctx.noBackupFilesDir.canonicalFile
        val fixture = File(noBackup, "backup_journal_probe_$id")
        require(fixture.canonicalFile.parentFile == noBackup) { "fixture escaped no_backup" }
        return fixture
    }

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
                val lockFile = java.io.File(ctx.noBackupFilesDir, "database_lifecycle.lock").canonicalFile
                val stat = android.system.Os.stat(lockFile.absolutePath)
                Bundle().apply {
                    putInt("pid", Process.myPid())
                    putBoolean("admitted", token != null && released)
                    putString("lockPath", lockFile.absolutePath)
                    putString("lockIdentity", "${stat.st_dev}:${stat.st_ino}")
                }
            }
            "probeBootSafe" -> Bundle().apply {
                putInt("pid", Process.myPid())
                putBoolean("safe", NativeBackupStartupGate.isSafeForDatabaseOrBoot(ctx))
            }
            // D4b-3: prove the OS releases a REAL exclusive owner after SIGKILL.
            // Witness exists only under a UUID-scoped synthetic probe directory.
            "kill_EXCLUSIVE_OWNER" -> {
                val root = ownerDeathFixture(ctx, arg)
                check(root.mkdir()) { "exclusive-owner witness fixture already exists" }
                val completed = NativeBackupStartupGate.withExclusiveFixtureOwnerForTest(ctx) {
                    val unexpected = NativeBackupStartupGate.acquireDatabaseSession(ctx)
                    if (unexpected != null) {
                        NativeBackupStartupGate.releaseDatabaseSession(unexpected)
                        throw IllegalStateException("exclusive owner admitted shared session")
                    }
                    check(!NativeBackupStartupGate.isSafeForDatabaseOrBoot(ctx))
                    FileOutputStream(File(root, "owner_witness.pid")).use { output ->
                        output.write(Process.myPid().toString().toByteArray(Charsets.UTF_8))
                        output.fd.sync()
                    }
                    Process.killProcess(Process.myPid())
                    throw IllegalStateException("OS refused to kill exclusive-owner probe")
                }
                check(completed != null) { "exclusive owner not acquired" }
                throw IllegalStateException("exclusive-owner kill did not occur")
            }
            "verify_EXCLUSIVE_OWNER_DEATH" -> {
                val root = ownerDeathFixture(ctx, arg)
                val witness = File(root, "owner_witness.pid")
                check(witness.isFile && witness.length() in 1L..16L) {
                    "no durable witness of acquiring exclusive owner before death"
                }
                val priorPid = witness.readText(Charsets.UTF_8).toInt()
                val token = NativeBackupStartupGate.acquireDatabaseSession(ctx)
                val released = token != null &&
                    NativeBackupStartupGate.releaseDatabaseSession(token)
                Bundle().apply {
                    putInt("pid", Process.myPid())
                    putInt("witnessPid", priorPid)
                    putBoolean("admitted", token != null && released)
                }
            }
            "cleanup_EXCLUSIVE_OWNER_DEATH" -> {
                val root = ownerDeathFixture(ctx, arg)
                check(File(root, "owner_witness.pid").delete() && root.delete()) {
                    "exclusive-owner fixture cleanup failed"
                }
                Bundle().apply { putBoolean("ok", true) }
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
