package ir.example.medication_companion

import android.content.Context
import android.os.Build
import android.os.UserManager
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.OverlappingFileLockException

/** M4-01D prerequisite: deny entry while any durable restore state is present.
 *
 * This guard is shared by main-engine startup and native boot receivers. Both
 * an in-process monitor and a kernel file lock are required: neither a Dart
 * static variable nor a momentary read of a journal serializes Flutter engines.
 * No destructive restore is implemented in this stage.
 */
internal object NativeBackupStartupGate {
    private val monitor = Any()

    private fun markersAbsent(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val users = context.getSystemService(Context.USER_SERVICE) as? UserManager
                ?: return false
            if (!users.isUserUnlocked) return false
        }

        val root = context.noBackupFilesDir.canonicalFile
        if (!root.isDirectory || !root.canRead()) return false
        val journal = File(root, "backup_journal")
        if (!journal.exists()) return true
        if (!journal.isDirectory || !journal.canRead() ||
            journal.canonicalFile.parentFile != root) return false

        // A journal or pending flag cannot be assumed harmless even when a
        // future parser detects a torn checksum. In this M4-01D prerequisite
        // build, only their *absence* permits normal DB access or scheduling.
        return !File(journal, "restore_journal.json").exists() &&
            !File(journal, "reconcile_pending.flag").exists() &&
            journal.listFiles() != null &&
            journal.listFiles().orEmpty().none {
                it.name.startsWith("restore_journal") ||
                    it.name.startsWith("reconcile_pending")
            }
    }

    /** Fail closed on locked CE storage, I/O failure or another process owning
     * the lifecycle lock. Do not block a broadcast thread waiting on a restore.
     */
    fun isSafeForDatabaseOrBoot(context: Context): Boolean = synchronized(monitor) {
        try {
            if (!markersAbsent(context)) return@synchronized false
            val root = context.noBackupFilesDir.canonicalFile
            val lockFile = File(root, "database_lifecycle.lock")
            RandomAccessFile(lockFile, "rw").use { handle ->
                val lock = try {
                    handle.channel.tryLock()
                } catch (_: OverlappingFileLockException) {
                    null
                } ?: return@synchronized false
                try {
                    // Recheck under the kernel lock: journal creation between
                    // the first check and lock acquisition must suppress entry.
                    markersAbsent(context)
                } finally {
                    lock.release()
                }
            }
        } catch (_: Exception) {
            false
        }
    }
}
