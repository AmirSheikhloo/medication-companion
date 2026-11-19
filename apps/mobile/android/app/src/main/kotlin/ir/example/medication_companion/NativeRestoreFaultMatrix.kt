package ir.example.medication_companion

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID

/** Device-only, destructive-to-ITS-OWN-SANDBOX fault matrix. The application's
 * actual Drift SQLite path is never opened, replaced or removed here.
 *
 * This tests repeatable byte-level rollback ordering and fsync on Android,
 * NOT a production recovery executor: live-handle closure, verified WAL
 * checkpoints, 17-table schema checks, notification reconciliation and real
 * OS process-death tests are still hard blockers for Phase B.
 */
internal object NativeRestoreFaultMatrix {
    private enum class Fault { AFTER_COPY, AFTER_SIDECARS, AFTER_RENAME, AFTER_JOURNAL }
    private enum class FreshCase {
        NO_ACTIVE, MATCHING_ACTIVE, DIFFERENT_ACTIVE, STALE_WAL, STALE_SHM, HOT_JOURNAL
    }
    private class InjectedCrash : RuntimeException()

    private const val maxTestBytes = 1024L * 1024L
    private val allowedProbeFiles = setOf(
        "old.sqlite", "candidate.sqlite", "old_db.master",
        "medication_companion_m1.sqlite", "medication_companion_m1.sqlite-wal",
        "medication_companion_m1.sqlite-shm", "medication_companion_m1.sqlite-journal",
        "install.ready", "old_reinstall.ready", "restore_journal.json",
    )

    /** Returns null on success, or a bounded debug-only diagnostic on failure.
     * A failed safety probe still prohibits enabling the actual restore path.
     */
    fun runDiagnostic(context: Context): String? {
        val operationId = UUID.randomUUID().toString()
        val journal = NativeRestoreJournal.debugOnlySandbox(context, operationId)
        val root = File(context.noBackupFilesDir, "backup_journal_probe_$operationId")
        var passed = false
        var stage = "INITIALIZE_SANDBOX"
        var failure: String? = null
        try {
            if (!root.mkdir()) throw IllegalStateException("sandbox is not fresh")
            Os.chmod(root.path, 448) // 0700
            NativeRestoreJournal.fsyncDirectory(context.noBackupFilesDir)
            val old = File(root, "old.sqlite")
            val candidate = File(root, "candidate.sqlite")
            val rollback = File(root, "old_db.master")
            val active = File(root, "medication_companion_m1.sqlite")
            stage = "CREATE_OLD_SQLITE"
            createFixture(old, "OLD")
            stage = "CREATE_NEW_SQLITE"
            createFixture(candidate, "NEW")
            stage = "CREATE_IMMUTABLE_MASTER"
            copyImmutable(old, rollback)
            val originalHash = fileSha256(old)
            val candidateHash = fileSha256(candidate)
            val seed = RestoreJournalEntry(
                operationId = operationId,
                backupId = UUID.randomUUID().toString(),
                oldAbsent = false,
                previousDbSize = old.length(),
                previousDbSha256 = originalHash,
                candidateSize = candidate.length(),
                candidateSha256 = candidateHash,
                activePath = active.canonicalPath,
                candidatePath = candidate.canonicalPath,
                rollbackPath = rollback.canonicalPath,
                state = RestoreJournalState.PREPARED,
            )
            // Each fault leaves durable intermediate disk state; a fresh
            // recovery call must complete from it without consuming the only
            // valid immutable rollback source.
            for (fault in Fault.entries) {
                stage = "PREPARE_${fault.name}"
                copyImmutable(candidate, active)
                journal.write(seed)
                journal.write(seed.copy(state = RestoreJournalState.OLD_SAVED))
                writeStaleSidecar(File(active.path + "-wal"))
                writeStaleSidecar(File(active.path + "-shm"))
                stage = "INJECT_${fault.name}"
                val crashed = runCatching { rollbackOldSaved(journal, root, fault) }
                val injectedFailure = crashed.exceptionOrNull()
                if (injectedFailure !is InjectedCrash) {
                    throw IllegalStateException(
                        "checkpoint $fault failed before injection: " +
                            "${injectedFailure?.javaClass?.simpleName ?: "NO_EXCEPTION"}: " +
                            injectedFailure?.message.orEmpty().take(140),
                        injectedFailure,
                    )
                }
                stage = "RECOVER_${fault.name}"
                rollbackOldSaved(journal, root, null)
                stage = "VERIFY_${fault.name}"
                verifySqlite(active, "OLD", seed.previousDbSize, originalHash)
                if (File(active.path + "-wal").exists() ||
                    File(active.path + "-shm").exists() ||
                    journal.read() != null ||
                    fileSha256(rollback) != originalHash ||
                    fileSha256(candidate) != candidateHash) {
                    throw IllegalStateException("rollback is not repeatable after $fault")
                }
            }

            stage = "HOT_ROLLBACK_JOURNAL"
            // A hot rollback journal is NOT an inert WAL/SHM sidecar: keep
            // every file and the journal untouched until handled by SQLite.
            copyImmutable(candidate, active)
            journal.write(seed)
            journal.write(seed.copy(state = RestoreJournalState.OLD_SAVED))
            writeStaleSidecar(File(active.path + "-journal"))
            if (runCatching { rollbackOldSaved(journal, root, null) }.isSuccess ||
                fileSha256(active) != candidateHash ||
                journal.read()?.state != RestoreJournalState.OLD_SAVED) {
                throw IllegalStateException("hot journal was not rejected")
            }
            if (!File(active.path + "-journal").delete()) {
                throw IllegalStateException("test journal removal failed")
            }
            NativeRestoreJournal.fsyncDirectory(root)
            rollbackOldSaved(journal, root, null)

            stage = "CORRUPTED_MASTER"
            // If the only rollback master is corrupted, the active candidate
            // and durable journal MUST remain untouched (fail closed).
            copyImmutable(candidate, active)
            journal.write(seed)
            journal.write(seed.copy(state = RestoreJournalState.OLD_SAVED))
            rollback.outputStream().use { output ->
                output.write(byteArrayOf(0x11, 0x22, 0x33))
                output.fd.sync()
            }
            NativeRestoreJournal.fsyncDirectory(root)
            if (runCatching { rollbackOldSaved(journal, root, null) }.isSuccess ||
                fileSha256(active) != candidateHash ||
                journal.read()?.state != RestoreJournalState.OLD_SAVED) {
                throw IllegalStateException("corrupted master was not rejected")
            }
            // D3c: six independent disposable fresh-install probe directories.
            for (freshCase in FreshCase.entries) {
                stage = "OLD_ABSENT_" + freshCase.name
                runOldAbsentCase(context, freshCase)
            }
            passed = true
        } catch (error: Exception) {
            passed = false
            Log.e("M4FaultMatrix", "Probe failed at $stage", error)
            failure = "$stage / ${error.javaClass.simpleName}: ${error.message.orEmpty().take(180)}"
        } finally {
            try {
                cleanupProbe(context, root)
            } catch (error: Exception) {
                passed = false
                Log.e("M4FaultMatrix", "Sandbox cleanup failed", error)
                failure = "CLEANUP_SANDBOX / ${error.javaClass.simpleName}: ${error.message.orEmpty().take(180)}"
            }
        }
        return if (passed) null else (failure ?: "UNKNOWN_FAULT_MATRIX_FAILURE")
    }


    /** Debug-only D3c scenarios. This must NEVER target the real Drift DB. */
    private fun runOldAbsentCase(context: Context, scenario: FreshCase) {
        val operationId = UUID.randomUUID().toString()
        val root = File(context.noBackupFilesDir, "backup_journal_probe_" + operationId)
        val journal = NativeRestoreJournal.debugOnlySandbox(context, operationId)
        try {
            if (!root.mkdir()) throw IllegalStateException("fresh sandbox not created")
            Os.chmod(root.path, 448) // 0700
            NativeRestoreJournal.fsyncDirectory(context.noBackupFilesDir)

            val candidate = File(root, "candidate.sqlite")
            val active = File(root, "medication_companion_m1.sqlite")
            val master = File(root, "old_db.master") // deliberately absent
            createFixture(candidate, "NEW")
            val candidateHash = fileSha256(candidate)
            val seed = RestoreJournalEntry(
                operationId = operationId,
                backupId = UUID.randomUUID().toString(),
                oldAbsent = true,
                previousDbSize = 0,
                previousDbSha256 = "",
                candidateSize = candidate.length(),
                candidateSha256 = candidateHash,
                activePath = active.canonicalPath,
                candidatePath = candidate.canonicalPath,
                rollbackPath = master.canonicalPath,
                state = RestoreJournalState.PREPARED,
            )
            journal.write(seed)
            val saved = seed.copy(state = RestoreJournalState.OLD_SAVED)
            journal.write(saved)

            when (scenario) {
                FreshCase.NO_ACTIVE -> Unit
                FreshCase.DIFFERENT_ACTIVE -> createFixture(active, "OTHER")
                else -> copyImmutable(candidate, active)
            }
            when (scenario) {
                FreshCase.STALE_WAL -> writeStaleSidecar(File(active.path + "-wal"))
                FreshCase.STALE_SHM -> writeStaleSidecar(File(active.path + "-shm"))
                FreshCase.HOT_JOURNAL -> writeStaleSidecar(File(active.path + "-journal"))
                else -> Unit
            }

            if (scenario == FreshCase.NO_ACTIVE || scenario == FreshCase.MATCHING_ACTIVE) {
                val installed = recoverOldAbsentSaved(journal, root)
                if (installed != (scenario == FreshCase.MATCHING_ACTIVE) ||
                    pathExistsNoFollow(master) ||
                    journal.read() != null ||
                    fileSha256(candidate) != candidateHash ||
                    pathExistsNoFollow(active) != installed ||
                    (installed && fileSha256(active) != candidateHash)) {
                    throw IllegalStateException("old_absent failed to converge: " + scenario.name)
                }
            } else {
                // Never erase a mismatched DB, sidecar, or nonterminal journal.
                val activeHash = fileSha256(active)
                val sidecar = when (scenario) {
                    FreshCase.STALE_WAL -> File(active.path + "-wal")
                    FreshCase.STALE_SHM -> File(active.path + "-shm")
                    FreshCase.HOT_JOURNAL -> File(active.path + "-journal")
                    else -> null
                }
                val outcome = runCatching { recoverOldAbsentSaved(journal, root) }
                if (outcome.isSuccess ||
                    journal.read() != saved ||
                    fileSha256(active) != activeHash ||
                    fileSha256(candidate) != candidateHash ||
                    (sidecar != null && !pathExistsNoFollow(sidecar)) ||
                    pathExistsNoFollow(master)) {
                    throw IllegalStateException("old_absent modified unknown state: " + scenario.name)
                }
            }
        } finally {
            cleanupProbe(context, root)
        }
    }

    private fun pathExistsNoFollow(path: File): Boolean = try {
        Os.lstat(path.path)
        true
    } catch (error: ErrnoException) {
        if (error.errno != OsConstants.ENOENT) throw error
        false
    }

    /** Synthetic cold-reentry state machine for the explicitly bound
     * oldAbsent=true case. NOT callable as a production restore handler.
     */
    private fun recoverOldAbsentSaved(journal: NativeRestoreJournal, root: File): Boolean {
        val record = journal.read() ?: throw IllegalStateException("missing fresh-install journal")
        if (!record.oldAbsent || record.state != RestoreJournalState.OLD_SAVED ||
            record.previousDbSize != 0L || record.previousDbSha256.isNotEmpty()) {
            throw IllegalStateException("unexpected fresh-install journal state")
        }

        val canonicalRoot = root.canonicalFile
        val active = File(canonicalRoot, "medication_companion_m1.sqlite")
        val candidate = File(canonicalRoot, "candidate.sqlite")
        val master = File(canonicalRoot, "old_db.master")
        if (File(record.activePath) != active ||
            File(record.candidatePath) != candidate ||
            File(record.rollbackPath) != master ||
            active.parentFile?.canonicalFile != canonicalRoot ||
            pathExistsNoFollow(master)) {
            throw IllegalStateException("unbound fresh-install paths")
        }

        // lstat also catches dangling symlinks; unknown sidecars are never
        // deleted to force a successful restore.
        for (suffix in listOf("-wal", "-shm", "-journal")) {
            if (pathExistsNoFollow(File(active.path + suffix))) {
                throw IllegalStateException("unexpected fresh-install sidecar")
            }
        }
        if (!pathExistsNoFollow(active)) {
            journal.write(record.copy(state = RestoreJournalState.ROLLED_BACK))
            journal.clearTerminal()
            return false
        }

        // Verify size, SHA-256, SQLite integrity, foreign keys, and v5 row
        // before recording NEW_INSTALLED, VERIFIED and durable COMMITTED.
        verifySqlite(active, "NEW", record.candidateSize, record.candidateSha256)
        journal.write(record.copy(state = RestoreJournalState.NEW_INSTALLED))
        journal.write(record.copy(state = RestoreJournalState.VERIFIED))
        journal.write(record.copy(state = RestoreJournalState.COMMITTED))
        journal.clearTerminal()
        return true
    }


    /** D3d debug-only, cross-process crash preparation. The process serving
     * this method is killed by a separate debug-only ContentProvider AFTER
     * all state below is fsynced. Only random sandbox SQLite files are used.
     */
    internal fun prepareProcessDeathSandbox(context: Context, id: String, checkpoint: String) {
        require(UUID.fromString(id).toString() == id)
        require(checkpoint == "OLD_SAVED" || checkpoint == "NEW_INSTALLED")
        val root = File(context.noBackupFilesDir, "backup_journal_probe_$id")
        val journal = NativeRestoreJournal.debugOnlySandbox(context, id)
        if (!root.mkdir()) throw IllegalStateException("process-death sandbox already exists")
        Os.chmod(root.path, 448) // 0700
        NativeRestoreJournal.fsyncDirectory(context.noBackupFilesDir)

        val old = File(root, "old.sqlite")
        val candidate = File(root, "candidate.sqlite")
        val master = File(root, "old_db.master")
        val active = File(root, "medication_companion_m1.sqlite")
        createFixture(old, "OLD")
        createFixture(candidate, "NEW")
        copyImmutable(old, master)
        val seed = RestoreJournalEntry(
            operationId = id,
            backupId = UUID.randomUUID().toString(),
            oldAbsent = false,
            previousDbSize = old.length(),
            previousDbSha256 = fileSha256(old),
            candidateSize = candidate.length(),
            candidateSha256 = fileSha256(candidate),
            activePath = active.canonicalPath,
            candidatePath = candidate.canonicalPath,
            rollbackPath = master.canonicalPath,
            state = RestoreJournalState.PREPARED,
        )
        journal.write(seed)
        journal.write(seed.copy(state = RestoreJournalState.OLD_SAVED))
        copyImmutable(candidate, active)
        if (checkpoint == "NEW_INSTALLED") {
            verifySqlite(active, "NEW", seed.candidateSize, seed.candidateSha256)
            journal.write(seed.copy(state = RestoreJournalState.NEW_INSTALLED))
        }
    }

    /** This runs only in a NEW Android process after the debug worker dies.
     * Return the durable terminal state; do not consume corrupt journals or
     * delete unknown DB sidecars. No real application DB is ever accessed.
     */
    internal fun recoverProcessDeathSandbox(context: Context, id: String, checkpoint: String): String {
        require(UUID.fromString(id).toString() == id)
        require(checkpoint == "OLD_SAVED" || checkpoint == "NEW_INSTALLED")
        val root = File(context.noBackupFilesDir, "backup_journal_probe_$id")
        val canonicalRoot = root.canonicalFile
        if (canonicalRoot.parentFile != context.noBackupFilesDir.canonicalFile ||
            !canonicalRoot.isDirectory) throw IllegalStateException("unsafe process-death sandbox")
        val journal = NativeRestoreJournal.debugOnlySandbox(context, id)
        val record = journal.read() ?: throw IllegalStateException("process-death journal missing")
        val expectedState = RestoreJournalState.valueOf(checkpoint)
        if (record.state != expectedState || record.oldAbsent ||
            record.operationId != id) throw IllegalStateException("wrong recovered checkpoint")

        val old = File(canonicalRoot, "old.sqlite")
        val master = File(canonicalRoot, "old_db.master")
        val candidate = File(canonicalRoot, "candidate.sqlite")
        val active = File(canonicalRoot, "medication_companion_m1.sqlite")
        if (record.activePath != active.path ||
            record.candidatePath != candidate.path ||
            record.rollbackPath != master.path) {
            throw IllegalStateException("unbound cross-process paths")
        }
        for (suffix in listOf("-wal", "-shm", "-journal")) {
            if (pathExistsNoFollow(File(active.path + suffix))) {
                throw IllegalStateException("unknown cross-process DB sidecar")
            }
        }
        verifySqlite(old, "OLD", record.previousDbSize, record.previousDbSha256)
        verifySqlite(master, "OLD", record.previousDbSize, record.previousDbSha256)
        verifySqlite(candidate, "NEW", record.candidateSize, record.candidateSha256)
        verifySqlite(active, "NEW", record.candidateSize, record.candidateSha256)

        val terminal = if (record.state == RestoreJournalState.OLD_SAVED) {
            val reinstall = File(canonicalRoot, "old_reinstall.ready")
            if (pathExistsNoFollow(reinstall)) throw IllegalStateException("unexpected reinstall temp")
            copyImmutable(master, reinstall)
            verifySqlite(reinstall, "OLD", record.previousDbSize, record.previousDbSha256)
            Os.rename(reinstall.path, active.path)
            NativeRestoreJournal.fsyncDirectory(canonicalRoot)
            verifySqlite(active, "OLD", record.previousDbSize, record.previousDbSha256)
            journal.write(record.copy(state = RestoreJournalState.ROLLED_BACK))
            RestoreJournalState.ROLLED_BACK
        } else {
            journal.write(record.copy(state = RestoreJournalState.VERIFIED))
            journal.write(record.copy(state = RestoreJournalState.COMMITTED))
            RestoreJournalState.COMMITTED
        }
        journal.clearTerminal()
        if (journal.read() != null ||
            fileSha256(master) != record.previousDbSha256 ||
            fileSha256(candidate) != record.candidateSha256) {
            throw IllegalStateException("cross-process recovery lost durable artifacts")
        }
        return terminal.name
    }

    /** Tests may erase only a validated, completed sandbox after asserting its
     * terminal result. A failed recovery leaves disk evidence for diagnosis.
     */
    internal fun cleanupCompletedProcessDeathSandbox(context: Context, id: String) {
        require(UUID.fromString(id).toString() == id)
        val root = File(context.noBackupFilesDir, "backup_journal_probe_$id")
        val journal = NativeRestoreJournal.debugOnlySandbox(context, id)
        if (journal.read() != null) throw IllegalStateException("nonterminal journal not cleaned")
        cleanupProbe(context, root)
    }

    private fun createFixture(path: File, value: String) {
        if (path.exists()) throw IllegalStateException("fixture path already exists")
        SQLiteDatabase.openOrCreateDatabase(path, null).use { db ->
            db.rawQuery("PRAGMA journal_mode=DELETE", null).use { cursor ->
                if (!cursor.moveToFirst() ||
                    cursor.getString(0).lowercase(Locale.ROOT) != "delete") {
                    throw IllegalStateException("test fixture is not rollback-journal SQLite")
                }
            }
            db.execSQL("PRAGMA user_version=5")
            db.execSQL("CREATE TABLE probe (id INTEGER PRIMARY KEY, value TEXT NOT NULL)")
            db.execSQL("INSERT INTO probe (id, value) VALUES (1, ?)", arrayOf(value))
        }
        // SQLite is closed: sync the fixture itself and its newly created
        // directory entry, without attempting to copy a live/WAL-mode file.
        FileOutputStream(path, true).use { it.fd.sync() }
        NativeRestoreJournal.fsyncDirectory(path.parentFile!!)
        verifySqlite(path, value, path.length(), fileSha256(path))
    }

    private fun fileSha256(path: File): String {
        if (!path.isFile || path.length() !in 1L..maxTestBytes ||
            (Os.lstat(path.path).st_mode and OsConstants.S_IFMT) != OsConstants.S_IFREG) {
            throw IllegalStateException("invalid probe file")
        }
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(path).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count == -1) break
                if (count == 0) throw IllegalStateException("short probe read")
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(Locale.ROOT, it.toInt() and 255) }
    }

    private fun verifySqlite(file: File, expected: String, size: Long, hash: String) {
        if (file.length() != size || fileSha256(file) != hash) {
            throw IllegalStateException("probe SQLite size/hash mismatch")
        }
        SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
            if (db.version != 5) throw IllegalStateException("probe schema version changed")
            db.rawQuery("PRAGMA integrity_check(10)", null).use { c ->
                if (!c.moveToFirst() || c.getString(0) != "ok" || c.moveToNext()) {
                    throw IllegalStateException("probe SQLite integrity failed")
                }
            }
            db.rawQuery("PRAGMA foreign_key_check", null).use { c ->
                if (c.moveToFirst()) throw IllegalStateException("probe SQLite FK failed")
            }
            db.rawQuery("SELECT value FROM probe WHERE id=1", null).use { c ->
                if (!c.moveToFirst() || c.getString(0) != expected || c.moveToNext()) {
                    throw IllegalStateException("probe SQLite value differs")
                }
            }
        }
    }

    /** O_EXCL prevents replacing an existing destination or following a
     * symlink. A prior unfinished *.ready file must be cleared explicitly by
     * the recovery state machine before invoking this copy operation.
     */
    private fun copyImmutable(source: File, target: File) {
        val parent = target.parentFile ?: throw IllegalStateException("missing target parent")
        if (parent.canonicalFile != source.parentFile?.canonicalFile) {
            throw IllegalStateException("probe crossed a directory")
        }
        if (target.exists() && !target.delete()) {
            throw IllegalStateException("cannot remove old probe target")
        }
        val fd = Os.open(
            target.path,
            OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_NOFOLLOW,
            384, // 0600
        )
        FileOutputStream(fd).use { output ->
            FileInputStream(source).use { input ->
                val bytes = ByteArray(64 * 1024)
                var total = 0L
                while (true) {
                    val count = input.read(bytes)
                    if (count == -1) break
                    if (count == 0) throw IllegalStateException("short copy")
                    total += count
                    if (total > maxTestBytes) throw IllegalStateException("oversized probe")
                    output.write(bytes, 0, count)
                }
                if (total < 4096) throw IllegalStateException("short SQLite image")
                output.fd.sync()
            }
        }
        NativeRestoreJournal.fsyncDirectory(parent)
    }

    private fun writeStaleSidecar(path: File) {
        if (path.exists()) throw IllegalStateException("sidecar already exists")
        FileOutputStream(path).use { output ->
            output.write(byteArrayOf(1, 2, 3, 4, 5, 6))
            output.fd.sync()
        }
        NativeRestoreJournal.fsyncDirectory(path.parentFile!!)
    }

    private fun deleteKnownTemporary(path: File) {
        if (!path.exists()) return
        if ((Os.lstat(path.path).st_mode and OsConstants.S_IFMT) != OsConstants.S_IFREG ||
            !path.delete()) throw IllegalStateException("unsafe temporary probe file")
        NativeRestoreJournal.fsyncDirectory(path.parentFile!!)
    }

    private fun rollbackOldSaved(
        journal: NativeRestoreJournal,
        root: File,
        injected: Fault?,
    ) {
        val record = journal.read() ?: throw IllegalStateException("missing recovery journal")
        if (record.state != RestoreJournalState.OLD_SAVED &&
            record.state != RestoreJournalState.ROLLED_BACK) {
            throw IllegalStateException("not a rollback state")
        }
        if (record.oldAbsent) throw IllegalStateException("old-absent handled separately")
        val active = File(record.activePath)
        val master = File(record.rollbackPath)
        val candidate = File(record.candidatePath)
        // Android may expose app-private storage via /data/user/0 while
        // canonicalPath resolves that same directory under /data/data.
        // Bind all paths to the *same canonical root* before comparing exact
        // filenames; never loosen this to prefix or suffix matching.
        val canonicalRoot = root.canonicalFile
        if (active != File(canonicalRoot, "medication_companion_m1.sqlite") ||
            master != File(canonicalRoot, "old_db.master") ||
            candidate != File(canonicalRoot, "candidate.sqlite") ||
            active.parentFile?.canonicalFile != canonicalRoot) {
            throw IllegalStateException("unbound probe paths")
        }
        // Verify the immutable master BEFORE touching the possibly damaged
        // new active database or any of its sidecars.
        verifySqlite(master, "OLD", record.previousDbSize, record.previousDbSha256)
        val install = File(root, "install.ready")
        val reinstall = File(root, "old_reinstall.ready")
        deleteKnownTemporary(install)
        deleteKnownTemporary(reinstall)
        copyImmutable(master, reinstall)
        if (injected == Fault.AFTER_COPY) throw InjectedCrash()

        // R7 requires a verified quiescent DB before this step in production.
        // This probe has no active SQLite handles by construction.
        if (File(active.path + "-journal").exists()) {
            throw IllegalStateException("hot rollback journal requires SQLite recovery")
        }
        for (suffix in listOf("-wal", "-shm")) {
            deleteKnownTemporary(File(active.path + suffix))
        }
        NativeRestoreJournal.fsyncDirectory(root)
        if (injected == Fault.AFTER_SIDECARS) throw InjectedCrash()

        Os.rename(reinstall.path, active.path)
        NativeRestoreJournal.fsyncDirectory(root)
        if (injected == Fault.AFTER_RENAME) throw InjectedCrash()

        verifySqlite(active, "OLD", record.previousDbSize, record.previousDbSha256)
        journal.write(record.copy(state = RestoreJournalState.ROLLED_BACK))
        if (injected == Fault.AFTER_JOURNAL) throw InjectedCrash()
        journal.clearTerminal()
    }

    private fun cleanupProbe(context: Context, root: File) {
        if (!root.exists()) return
        val expectedPrefix = "backup_journal_probe_"
        if (!root.name.startsWith(expectedPrefix) ||
            root.parentFile?.canonicalFile != context.noBackupFilesDir.canonicalFile ||
            (Os.lstat(root.path).st_mode and OsConstants.S_IFMT) != OsConstants.S_IFDIR) {
            throw IllegalStateException("untrusted probe cleanup target")
        }
        for (item in root.listFiles().orEmpty()) {
            if (item.name !in allowedProbeFiles &&
                !Regex("restore_journal\\.[a-f0-9-]+\\.tmp").matches(item.name)) {
                throw IllegalStateException("unexpected probe cleanup path")
            }
            if ((Os.lstat(item.path).st_mode and OsConstants.S_IFMT) != OsConstants.S_IFREG ||
                !item.delete()) throw IllegalStateException("probe cleanup refused")
        }
        if (!root.delete()) throw IllegalStateException("probe directory cleanup refused")
        NativeRestoreJournal.fsyncDirectory(context.noBackupFilesDir)
    }
}
