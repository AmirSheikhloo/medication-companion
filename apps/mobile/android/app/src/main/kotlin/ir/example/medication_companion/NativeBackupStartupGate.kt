package ir.example.medication_companion

import android.content.Context
import android.os.Build
import android.os.UserManager
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.FileLock
import java.nio.channels.OverlappingFileLockException
import java.util.UUID

/** M4-01D prerequisite: deny entry while any durable restore state is present.
 *
 * This guard is shared by main-engine startup and native boot receivers. Both
 * an in-process monitor and a kernel file lock are required: neither a Dart
 * static variable nor a momentary read of a journal serializes Flutter engines.
 * No destructive restore is implemented in this stage.
 */
internal object NativeBackupStartupGate {
    private val monitor = Any()
    private var sharedLeaseFile: RandomAccessFile? = null
    private var sharedLeaseLock: FileLock? = null
    private val activeLeaseIds = mutableSetOf<String>()

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
            // Existing in-process DB sessions already hold a native shared
            // lease, so they cannot overlap a correctly acquired restore
            // exclusive lock. Java disallows overlapping locks in one VM.
            if (activeLeaseIds.isNotEmpty()) {
                return@synchronized sharedLeaseLock?.isValid == true &&
                    markersAbsent(context)
            }
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

    /** A native, process-wide OS lease that stays held for the lifetime of
     * every Dart/Drift database session. All engines share one kernel lock:
     * Java FileChannel prohibits overlapping locks within a JVM. A separate
     * native restore owner must later acquire this lock EXCLUSIVELY and must
     * fail if any such session is active.
     *
     * Returns null (fail closed) when CE storage, journal or lock is unsafe.
     */
    fun acquireDatabaseSession(context: Context): String? = synchronized(monitor) {
        try {
            if (!markersAbsent(context)) return@synchronized null
            if (activeLeaseIds.isEmpty()) {
                val root = context.noBackupFilesDir.canonicalFile
                val file = RandomAccessFile(File(root, "database_lifecycle.lock"), "rw")
                var lock: FileLock? = null
                try {
                    lock = try {
                        file.channel.tryLock(0L, Long.MAX_VALUE, true)
                    } catch (_: OverlappingFileLockException) { null }
                    if (lock == null || !markersAbsent(context)) {
                        return@synchronized null
                    }
                    sharedLeaseFile = file
                    sharedLeaseLock = lock
                } finally {
                    // If any intermediate operation fails, the file channel
                    // must not leak, and no orphan lock may outlive its token.
                    if (sharedLeaseFile !== file) {
                        try { lock?.release() } catch (_: Exception) {}
                        try { file.close() } catch (_: Exception) {}
                    }
                }
            } else if (sharedLeaseLock?.isValid != true) {
                // Never reissue a token after a native lock was unexpectedly
                // lost; the app must close and restart for safe recovery.
                return@synchronized null
            }
            val id = UUID.randomUUID().toString()
            activeLeaseIds.add(id)
            id
        } catch (_: Exception) {
            null
        }
    }

    /** Only the holder of an issued token can relinquish its lifetime lease.
     * Unknown and repeated releases fail closed and cannot free others' locks.
     */
    fun releaseDatabaseSession(token: String): Boolean = synchronized(monitor) {
        if (!activeLeaseIds.remove(token)) return@synchronized false
        if (activeLeaseIds.isEmpty()) {
            try {
                sharedLeaseLock?.release()
                sharedLeaseFile?.close()
            } catch (_: Exception) {
                // Fail closed: a subsequent admission will not trust an
                // invalid native lock. The kernel releases it on process exit.
                return@synchronized false
            } finally {
                sharedLeaseLock = null
                sharedLeaseFile = null
            }
        }
        true
    }
}
