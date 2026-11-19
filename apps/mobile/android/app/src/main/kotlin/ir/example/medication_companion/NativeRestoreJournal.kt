package ir.example.medication_companion

import android.content.Context
import android.system.Os
import android.system.OsConstants
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID

/** The disk protocol for a future M4-01D Phase B owner. This class DOES NOT
 * acquire restore ownership or install/rollback a database. It is currently
 * exercised only against a freshly created, separate debug probe directory.
 * Production use remains blocked until recovery and all kill points exist.
 */
internal enum class RestoreJournalState {
    PREPARED, OLD_SAVED, NEW_INSTALLED, VERIFIED, COMMITTED, ROLLED_BACK
}

internal data class RestoreJournalEntry(
    val operationId: String,
    val backupId: String,
    val oldAbsent: Boolean,
    val previousDbSize: Long,
    val previousDbSha256: String,
    val candidateSize: Long,
    val candidateSha256: String,
    val activePath: String,
    val candidatePath: String,
    val rollbackPath: String,
    val state: RestoreJournalState,
)

internal class NativeRestoreJournal private constructor(
    private val context: Context,
    private val directory: File,
) {
    companion object {
        private const val journalName = "restore_journal.json"
        private const val maxJournalBytes = 8192L
        private const val maxCandidateBytes = 64L * 1024 * 1024
        private val hashPattern = Regex("[0-9a-f]{64}")
        private val states = RestoreJournalState.entries.map { it.name }.toSet()

        /** There is intentionally NO production factory until the exclusive
         * owner and complete crash-safe recovery state machine are connected.
         */
        internal fun debugOnlySandbox(context: Context, id: String): NativeRestoreJournal {
            require(UUID.fromString(id).toString() == id)
            return NativeRestoreJournal(
                context,
                File(context.noBackupFilesDir, "backup_journal_probe_$id"),
            )
        }

        fun debugDurabilityProbe(context: Context): Boolean {
            val id = UUID.randomUUID().toString()
            val store = debugOnlySandbox(context, id)
            var passed = false
            try {
                // Probe app-private directories actually mounted on the
                // emulator, not a host-filesystem substitute for Android.
                if (Os.stat(context.filesDir.path).st_dev !=
                    Os.stat(context.noBackupFilesDir.path).st_dev) return false
                // No file in the active SQLite directory is ever opened.
                val seed = RestoreJournalEntry(
                    operationId = id,
                    backupId = UUID.randomUUID().toString(),
                    oldAbsent = false,
                    previousDbSize = 4096,
                    previousDbSha256 = "a".repeat(64),
                    candidateSize = 8192,
                    candidateSha256 = "b".repeat(64),
                    activePath = File(context.filesDir, "medication_companion_m1.sqlite").canonicalPath,
                    candidatePath = File(store.directory, "test_candidate.sqlite").canonicalPath,
                    rollbackPath = File(store.directory, "test_rollback.master").canonicalPath,
                    state = RestoreJournalState.PREPARED,
                )
                store.write(seed)
                if (store.read() != seed) return false
                // Every transition must be independently parseable from disk,
                // not inferred from an in-memory object or successful rename.
                var previous = seed
                for (state in listOf(
                    RestoreJournalState.OLD_SAVED,
                    RestoreJournalState.NEW_INSTALLED,
                    RestoreJournalState.VERIFIED,
                    RestoreJournalState.COMMITTED,
                )) {
                    val next = previous.copy(state = state)
                    store.write(next)
                    if (store.read() != next) return false
                    previous = next
                }
                // Reversing a durable transition is forbidden.
                if (runCatching { store.write(seed) }.isSuccess) return false
                store.clearTerminal()
                if (store.read() != null) return false

                // Deliberately corrupt a separate probe journal: it MUST fail
                // closed, not silently parse as an empty/clean journal.
                store.write(seed)
                val journal = File(store.directory, journalName)
                val bytes = journal.readBytes()
                bytes[bytes.lastIndex - 6] = (bytes[bytes.lastIndex - 6].toInt() xor 1).toByte()
                journal.writeBytes(bytes)
                if (runCatching { store.read() }.isSuccess) return false
                if (runCatching { store.write(seed.copy(state = RestoreJournalState.OLD_SAVED)) }.isSuccess) {
                    return false
                }
                passed = true
            } catch (_: Exception) {
                return false
            } finally {
                // Only our unpredictable, newly created probe directory is
                // eligible for cleanup. Never touch backup_journal or live DB.
                try {
                    val items = store.directory.listFiles().orEmpty()
                    for (item in items) {
                        if (item.name != journalName &&
                            !Regex("restore_journal\\.[a-f0-9-]+\\.tmp").matches(item.name)) {
                            throw IllegalStateException("unexpected debug probe file")
                        }
                        if (!item.isFile || !item.delete()) {
                            throw IllegalStateException("debug probe cleanup failed")
                        }
                    }
                    if (store.directory.exists() && !store.directory.delete()) {
                        throw IllegalStateException("debug probe dir cleanup failed")
                    }
                    fsyncDirectory(context.noBackupFilesDir)
                } catch (_: Exception) {
                    passed = false
                }
            }
            return passed
        }

        internal fun fsyncDirectory(dir: File) {
            // The Android public SDK exposes O_RDONLY, but not O_DIRECTORY.
            // Validate the descriptor target before opening and fsyncing it.
            if ((Os.lstat(dir.path).st_mode and OsConstants.S_IFMT) != OsConstants.S_IFDIR) {
                throw IllegalStateException("cannot fsync a non-directory")
            }
            val fd = Os.open(dir.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
            try {
                if ((Os.fstat(fd).st_mode and OsConstants.S_IFMT) != OsConstants.S_IFDIR) {
                    throw IllegalStateException("directory descriptor changed")
                }
                Os.fsync(fd)
            } finally { Os.close(fd) }
        }

        private fun sha256(bytes: ByteArray): String =
            MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {
                "%02x".format(Locale.ROOT, it.toInt() and 0xff)
            }

        private fun validUuid(value: String): Boolean =
            runCatching { UUID.fromString(value).toString() == value }.getOrDefault(false)
    }

    private val file: File get() = File(directory, journalName)

    private fun ensureDirectory() {
        val root = context.noBackupFilesDir.canonicalFile
        if (!root.isDirectory || !root.canRead() || !root.canWrite() ||
            directory.parentFile?.canonicalFile != root ||
            !directory.name.matches(Regex("backup_journal_probe_[a-f0-9-]{36}"))) {
            throw IllegalStateException("unsafe journal directory")
        }
        if (!directory.exists()) {
            if (!directory.mkdir()) throw IllegalStateException("journal mkdir failed")
            Os.chmod(directory.path, 448) // 0700
            fsyncDirectory(root)
        }
        val mode = Os.lstat(directory.path).st_mode and OsConstants.S_IFMT
        if (mode != OsConstants.S_IFDIR ||
            !directory.isDirectory || directory.canonicalFile.parentFile != root) {
            throw IllegalStateException("journal directory changed")
        }
        if (Os.stat(directory.path).st_dev != Os.stat(root.path).st_dev) {
            throw IllegalStateException("journal crossed filesystem")
        }
    }

    private fun validate(entry: RestoreJournalEntry) {
        if (!validUuid(entry.operationId) || !validUuid(entry.backupId) ||
            entry.previousDbSize < 0 ||
            entry.candidateSize !in 4096L..maxCandidateBytes ||
            !hashPattern.matches(entry.candidateSha256) ||
            (entry.oldAbsent && (entry.previousDbSize != 0L || entry.previousDbSha256.isNotEmpty())) ||
            (!entry.oldAbsent && (entry.previousDbSize < 4096L || !hashPattern.matches(entry.previousDbSha256)))) {
            throw IllegalArgumentException("invalid restore journal metadata")
        }
        // A canonical journal must never point outside app-private storage.
        val privateRoot = context.applicationInfo.dataDir?.let(::File)?.canonicalFile
            ?: throw IllegalStateException("app-private root missing")
        for (path in listOf(entry.activePath, entry.candidatePath, entry.rollbackPath)) {
            val canonical = File(path).canonicalFile
            if (!File(path).isAbsolute || !canonical.path.startsWith(privateRoot.path + File.separator)) {
                throw IllegalArgumentException("journal path is not private")
            }
        }
        if (!entry.activePath.endsWith("/medication_companion_m1.sqlite") &&
            !entry.activePath.endsWith("/medication_companion_m1.db")) {
            throw IllegalArgumentException("unexpected database basename")
        }
        if (!entry.candidatePath.endsWith(".sqlite") ||
            !entry.rollbackPath.endsWith(".master")) {
            throw IllegalArgumentException("unexpected restore artifact basename")
        }
    }

    private fun fields(entry: RestoreJournalEntry): String = buildString {
        append("{\"journal_version\":1")
        append(",\"operation_id\":").append(JSONObject.quote(entry.operationId))
        append(",\"schema_version\":5")
        append(",\"backup_id\":").append(JSONObject.quote(entry.backupId))
        append(",\"old_absent\":").append(entry.oldAbsent)
        append(",\"previous_db_size\":").append(entry.previousDbSize)
        append(",\"previous_db_sha256\":").append(JSONObject.quote(entry.previousDbSha256))
        append(",\"candidate_size\":").append(entry.candidateSize)
        append(",\"candidate_sha256\":").append(JSONObject.quote(entry.candidateSha256))
        append(",\"active_db_path\":").append(JSONObject.quote(entry.activePath))
        append(",\"candidate_path\":").append(JSONObject.quote(entry.candidatePath))
        append(",\"rollback_master_path\":").append(JSONObject.quote(entry.rollbackPath))
        append(",\"state\":").append(JSONObject.quote(entry.state.name))
    }

    private fun canonical(entry: RestoreJournalEntry): ByteArray {
        validate(entry)
        val body = fields(entry)
        val digest = sha256("$body}".toByteArray(StandardCharsets.UTF_8))
        return "$body,\"journal_sha256\":\"$digest\"}".toByteArray(StandardCharsets.UTF_8)
    }

    fun read(): RestoreJournalEntry? {
        if (!directory.exists()) return null
        ensureDirectory()
        if (!file.exists()) return null
        if (!file.isFile || file.length() !in 1L..maxJournalBytes ||
            (Os.lstat(file.path).st_mode and OsConstants.S_IFMT) != OsConstants.S_IFREG ||
            file.canonicalFile != File(directory.canonicalFile, journalName)) {
            throw IllegalStateException("ambiguous/corrupt restore journal")
        }
        // Never allocate according to an untrusted length after the check;
        // the file could have changed between stat and opening the handle.
        val raw = FileInputStream(file).use { input ->
            val bytes = ByteArray(maxJournalBytes.toInt() + 1)
            var count = 0
            while (count < bytes.size) {
                val read = input.read(bytes, count, bytes.size - count)
                if (read < 0) break
                if (read == 0) throw IllegalStateException("short journal read")
                count += read
            }
            if (count !in 1..maxJournalBytes.toInt()) {
                throw IllegalStateException("oversized or empty restore journal")
            }
            bytes.copyOf(count)
        }
        val content = String(raw, StandardCharsets.UTF_8)
        val json = JSONObject(content)
        val keys = setOf(
            "journal_version", "operation_id", "schema_version", "backup_id", "old_absent",
            "previous_db_size", "previous_db_sha256", "candidate_size", "candidate_sha256",
            "active_db_path", "candidate_path", "rollback_master_path", "state", "journal_sha256",
        )
        if (json.length() != keys.size || json.keys().asSequence().toSet() != keys ||
            json.getInt("journal_version") != 1 || json.getInt("schema_version") != 5 ||
            json.get("old_absent") !is Boolean ||
            json.get("previous_db_size") !is Long && json.get("previous_db_size") !is Int ||
            json.get("candidate_size") !is Long && json.get("candidate_size") !is Int ||
            !states.contains(json.getString("state"))) {
            throw IllegalStateException("unexpected journal fields")
        }
        val record = RestoreJournalEntry(
            operationId = json.getString("operation_id"),
            backupId = json.getString("backup_id"),
            oldAbsent = json.getBoolean("old_absent"),
            previousDbSize = json.getLong("previous_db_size"),
            previousDbSha256 = json.getString("previous_db_sha256"),
            candidateSize = json.getLong("candidate_size"),
            candidateSha256 = json.getString("candidate_sha256"),
            activePath = json.getString("active_db_path"),
            candidatePath = json.getString("candidate_path"),
            rollbackPath = json.getString("rollback_master_path"),
            state = RestoreJournalState.valueOf(json.getString("state")),
        )
        // Byte-exact canonical comparison detects any duplicate key, unknown
        // spelling, whitespace ambiguity, noncanonical number or torn write.
        if (!raw.contentEquals(canonical(record))) {
            throw IllegalStateException("journal checksum or canonical form mismatch")
        }
        return record
    }

    fun write(next: RestoreJournalEntry) {
        ensureDirectory()
        val previous = read()
        val allowed = when (previous?.state) {
            null -> next.state == RestoreJournalState.PREPARED
            RestoreJournalState.PREPARED -> next.state in setOf(
                RestoreJournalState.PREPARED, RestoreJournalState.OLD_SAVED, RestoreJournalState.ROLLED_BACK)
            RestoreJournalState.OLD_SAVED -> next.state in setOf(
                RestoreJournalState.OLD_SAVED, RestoreJournalState.NEW_INSTALLED, RestoreJournalState.ROLLED_BACK)
            RestoreJournalState.NEW_INSTALLED -> next.state in setOf(
                RestoreJournalState.NEW_INSTALLED, RestoreJournalState.VERIFIED, RestoreJournalState.ROLLED_BACK)
            RestoreJournalState.VERIFIED -> next.state in setOf(
                RestoreJournalState.VERIFIED, RestoreJournalState.COMMITTED, RestoreJournalState.ROLLED_BACK)
            RestoreJournalState.COMMITTED -> next.state in setOf(
                RestoreJournalState.COMMITTED, RestoreJournalState.ROLLED_BACK)
            RestoreJournalState.ROLLED_BACK -> next.state == RestoreJournalState.ROLLED_BACK
        }
        if (!allowed || previous != null && previous.copy(state = next.state) != next) {
            throw IllegalStateException("invalid journal transition or changed binding")
        }
        val bytes = canonical(next)
        if (bytes.size > maxJournalBytes) throw IllegalStateException("journal too large")
        val temporary = File(directory, "restore_journal.${UUID.randomUUID()}.tmp")
        val fd = Os.open(
            temporary.path,
            OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_WRONLY or OsConstants.O_NOFOLLOW,
            384, // 0600
        )
        var renamed = false
        try {
            try {
                var offset = 0
                while (offset < bytes.size) {
                    val count = Os.write(fd, bytes, offset, bytes.size - offset)
                    if (count <= 0) throw IllegalStateException("short journal write")
                    offset += count
                }
                Os.fsync(fd)
            } finally { Os.close(fd) }
            Os.rename(temporary.path, file.path)
            renamed = true
            fsyncDirectory(directory)
            if (read() != next) throw IllegalStateException("journal verification failed")
        } finally {
            // If rename succeeded, the committed journal remains durable;
            // never erase it merely because the read-back failed.
            if (!renamed && temporary.exists()) temporary.delete()
        }
    }

    fun clearTerminal() {
        val current = read() ?: return
        if (current.state != RestoreJournalState.COMMITTED &&
            current.state != RestoreJournalState.ROLLED_BACK) {
            throw IllegalStateException("cannot erase a nonterminal journal")
        }
        // Android's public Os facade does not expose unlink(). File.delete()
        // performs the unlink; parent-directory fsync makes it durable.
        if (!file.delete()) throw IllegalStateException("journal unlink failed")
        fsyncDirectory(directory)
    }
}
