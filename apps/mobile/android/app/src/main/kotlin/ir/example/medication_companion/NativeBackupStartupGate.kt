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
    private var restoreOwnerFile: RandomAccessFile? = null
    private var restoreOwnerLock: FileLock? = null
    private var restoreOwnerToken: String? = null

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

    /** The future Phase B orchestrator MUST take this exclusive OS lease
     * before creating any durable marker, stopping alarms or touching SQLite.
     * There is deliberately no runtime MethodChannel to obtain this token yet:
     * consent, quiescence and crash-safe journal operations are not ready.
     */
    private fun acquireRestoreOwner(context: Context): String? = synchronized(monitor) {
        try {
            if (restoreOwnerToken != null || activeLeaseIds.isNotEmpty() ||
                !markersAbsent(context)) return@synchronized null

            val root = context.noBackupFilesDir.canonicalFile
            val file = RandomAccessFile(File(root, "database_lifecycle.lock"), "rw")
            var lock: FileLock? = null
            try {
                lock = try {
                    file.channel.tryLock()
                } catch (_: OverlappingFileLockException) { null }
                if (lock == null || !markersAbsent(context)) return@synchronized null
                val token = UUID.randomUUID().toString()
                restoreOwnerFile = file
                restoreOwnerLock = lock
                restoreOwnerToken = token
                token
            } finally {
                if (restoreOwnerFile !== file) {
                    try { lock?.release() } catch (_: Exception) {}
                    try { file.close() } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) { null }
    }

    private fun releaseRestoreOwner(token: String): Boolean = synchronized(monitor) {
        if (token != restoreOwnerToken) return@synchronized false
        try {
            restoreOwnerLock?.release()
            restoreOwnerFile?.close()
        } catch (_: Exception) {
            return@synchronized false
        } finally {
            restoreOwnerLock = null
            restoreOwnerFile = null
            restoreOwnerToken = null
        }
        true
    }

    /**
     * D4b-2 fixture-only boundary: run non-mutating verification while the
     * same native/OS exclusive owner is held. This is deliberately NOT a
     * Flutter MethodChannel and must never be used as authorization for
     * replacing the actual app database or cancelling reminders.
     *
     * Null means exclusive admission was denied (existing shared session,
     * another restore owner, pending recovery marker or unavailable storage).
     * The caller must use synthetic isolated fixtures, and the lease remains
     * held until the callback returns or throws.
     */
    internal fun withExclusiveFixtureOwnerForTest(
        context: Context,
        verifyReadOnly: () -> Boolean,
    ): Boolean? {
        val owner = acquireRestoreOwner(context) ?: return null
        try {
            return verifyReadOnly()
        } finally {
            if (!releaseRestoreOwner(owner)) {
                throw IllegalStateException("Exclusive fixture owner release could not be verified")
            }
        }
    }

    /** Debug-only, non-destructive proof of lock exclusion. It performs no DB
     * I/O, writes no journal or reconcile marker and always releases tokens.
     * The caller must ensure that the normal medication screen is closed.
     */
    fun testLockExclusion(context: Context): Boolean = synchronized(monitor) {
        if (activeLeaseIds.isNotEmpty() || restoreOwnerToken != null) {
            return@synchronized false
        }
        val shared = acquireDatabaseSession(context) ?: return@synchronized false
        var releasedShared = false
        val firstPhase = try {
            val unexpectedRestore = acquireRestoreOwner(context)
            try {
                unexpectedRestore == null && isSafeForDatabaseOrBoot(context)
            } finally {
                if (unexpectedRestore != null) releaseRestoreOwner(unexpectedRestore)
            }
        } finally {
            releasedShared = releaseDatabaseSession(shared)
        }
        if (!firstPhase || !releasedShared) return@synchronized false

        val exclusive = acquireRestoreOwner(context) ?: return@synchronized false
        var releasedExclusive = false
        val secondPhase = try {
            val unexpectedShared = acquireDatabaseSession(context)
            val unexpectedRestore = acquireRestoreOwner(context)
            try {
                unexpectedShared == null && unexpectedRestore == null &&
                    !isSafeForDatabaseOrBoot(context)
            } finally {
                if (unexpectedShared != null) releaseDatabaseSession(unexpectedShared)
                if (unexpectedRestore != null) releaseRestoreOwner(unexpectedRestore)
            }
        } finally {
            releasedExclusive = releaseRestoreOwner(exclusive)
        }
        if (!secondPhase || !releasedExclusive) return@synchronized false

        val finalShared = acquireDatabaseSession(context) ?: return@synchronized false
        releaseDatabaseSession(finalShared)
    }
}
