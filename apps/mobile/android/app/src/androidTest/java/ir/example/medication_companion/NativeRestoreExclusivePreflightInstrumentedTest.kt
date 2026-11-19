package ir.example.medication_companion

import android.content.Context
import android.content.ContextWrapper
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.os.Process
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.FileInputStream
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * D4b-2 native OS ownership and read-only recheck proof on synthetic fixtures.
 *
 * There is no callable production restore API here. No test touches Drift's
 * medication_companion_m1 database, alarms, rollback master or journal.
 */
@RunWith(AndroidJUnit4::class)
class NativeRestoreExclusivePreflightInstrumentedTest {
    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun otherProcessCanAcquireSession(): Boolean {
        val uri = Uri.parse("content://${context.packageName}.m4killprobe")
        val response = context.contentResolver.call(uri, "probeAcquireSession", null, null)
        assertNotNull("Debug second-process probe is unavailable", response)
        assertNotEquals("Probe must execute in another Android PID",
            Process.myPid(), response!!.getInt("pid"))
        val ownLock = File(context.noBackupFilesDir, "database_lifecycle.lock").canonicalFile
        val ownStat = android.system.Os.stat(ownLock.absolutePath)
        assertEquals("Debug processes targeted different lifecycle paths",
            ownLock.absolutePath, response.getString("lockPath"))
        assertEquals("Debug processes targeted different lifecycle inodes",
            "${ownStat.st_dev}:${ownStat.st_ino}", response.getString("lockIdentity"))
        return response.getBoolean("admitted")
    }

    private fun otherProcessBootIsSafe(): Boolean {
        val response = context.contentResolver.call(
            Uri.parse("content://${context.packageName}.m4killprobe"),
            "probeBootSafe", null, null,
        )
        assertNotNull("Debug second-process boot probe is unavailable", response)
        assertNotEquals("Boot probe must execute in a different Android PID",
            Process.myPid(), response!!.getInt("pid"))
        return response.getBoolean("safe")
    }

    private fun fixture(run: (File, File) -> Unit) {
        val root = File(context.noBackupFilesDir, "backup_journal_probe_${UUID.randomUUID()}")
        assertTrue(root.mkdir())
        val live = File(root, "synthetic-live.sqlite")
        val candidate = File(root, "synthetic-candidate.sqlite")
        try {
            SQLiteDatabase.openOrCreateDatabase(live, null).use { db ->
                db.execSQL("PRAGMA user_version=5")
                db.execSQL("CREATE TABLE fixture_rows(id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
                db.execSQL("INSERT INTO fixture_rows(id,payload) VALUES('id1','ABCD')")
            }
            live.copyTo(candidate)
            run(live, candidate)
            assertFalse(File(context.noBackupFilesDir, "backup_journal/restore_journal.json").exists())
            assertFalse(File(context.noBackupFilesDir, "backup_journal/reconcile_pending.flag").exists())
        } finally {
            assertTrue("Synthetic fixture cleanup failed", root.deleteRecursively())
        }
    }

    private fun logicalDigest(live: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        SQLiteDatabase.openDatabase(live.absolutePath, null, SQLiteDatabase.OPEN_READONLY).use { db ->
            db.rawQuery("PRAGMA user_version", null).use { cursor ->
                assertTrue(cursor.moveToFirst())
                digest.update(cursor.getInt(0).toString().toByteArray(Charsets.UTF_8))
            }
            db.rawQuery("SELECT id,payload FROM fixture_rows ORDER BY id", null).use { cursor ->
                while (cursor.moveToNext()) {
                    for (column in 0..1) {
                        val bytes = cursor.getString(column).toByteArray(Charsets.UTF_8)
                        digest.update(bytes.size.toString().toByteArray(Charsets.UTF_8))
                        digest.update(':'.code.toByte())
                        digest.update(bytes)
                    }
                }
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private data class CandidateSeal(val size: Long, val sha256: String)

    private fun candidateSeal(candidate: File): CandidateSeal {
        val size = candidate.length()
        require(size in 1..(64L * 1024L * 1024L))
        val digest = MessageDigest.getInstance("SHA-256")
        var total = 0L
        FileInputStream(candidate).use { source ->
            val chunk = ByteArray(64 * 1024)
            while (true) {
                val count = source.read(chunk)
                if (count < 0) break
                total += count
                require(total <= 64L * 1024L * 1024L)
                digest.update(chunk, 0, count)
            }
        }
        require(total == size)
        return CandidateSeal(total, digest.digest().joinToString("") { "%02x".format(it) })
    }

    private fun verifyUnderExclusive(
        live: File, candidate: File,
        expectedLive: String, expectedCandidate: CandidateSeal,
    ): Boolean? = NativeBackupStartupGate.withExclusiveFixtureOwnerForTest(context) {
        // This check must be performed before marker creation, alarm changes,
        // a journal write, or any actual SQLite replacement.
        // Exercise both admission paths before the OTHER process checks the
        // kernel exclusion; neither may open/close a second file descriptor
        // and silently drop the owner's POSIX file lock.
        assertNull(NativeBackupStartupGate.acquireDatabaseSession(context))
        assertFalse(NativeBackupStartupGate.isSafeForDatabaseOrBoot(context))
        assertFalse(otherProcessCanAcquireSession())
        assertFalse(otherProcessBootIsSafe())
        logicalDigest(live) == expectedLive &&
            candidateSeal(candidate) == expectedCandidate
    }

    @Test
    fun ownerDeniedUntilAllSharedSessionsCloseAndBlocksNewAdmission() {
        fixture { live, candidate ->
            val first = NativeBackupStartupGate.acquireDatabaseSession(context)
            val second = NativeBackupStartupGate.acquireDatabaseSession(context)
            assertNotNull(first)
            assertNotNull(second)
            val expectedLive = logicalDigest(live)
            val expectedCandidate = candidateSeal(candidate)
            assertTrue(otherProcessCanAcquireSession())
            try {
                assertNull(verifyUnderExclusive(live, candidate, expectedLive, expectedCandidate))
                assertTrue(NativeBackupStartupGate.releaseDatabaseSession(first!!))
                assertNull(verifyUnderExclusive(live, candidate, expectedLive, expectedCandidate))
            } finally {
                assertTrue(NativeBackupStartupGate.releaseDatabaseSession(second!!))
            }
            assertEquals(true, verifyUnderExclusive(live, candidate, expectedLive, expectedCandidate))
            assertTrue(otherProcessCanAcquireSession())
            assertTrue(otherProcessBootIsSafe())
            val after = NativeBackupStartupGate.acquireDatabaseSession(context)
            assertNotNull(after)
            assertTrue(NativeBackupStartupGate.releaseDatabaseSession(after!!))
        }
    }

    @Test
    fun sameCountLiveEditAndSameSizeCandidateTamperingAreRejectedUnderOwner() {
        fixture { live, candidate ->
            val expectedLive = logicalDigest(live)
            val expectedCandidate = candidateSeal(candidate)
            assertEquals(true, verifyUnderExclusive(live, candidate, expectedLive, expectedCandidate))
            assertEquals(true, verifyUnderExclusive(live, candidate, expectedLive, expectedCandidate))

            SQLiteDatabase.openDatabase(live.absolutePath, null, SQLiteDatabase.OPEN_READWRITE).use {
                it.execSQL("UPDATE fixture_rows SET payload='WXYZ' WHERE id='id1'")
            }
            assertEquals(false, verifyUnderExclusive(live, candidate, expectedLive, expectedCandidate))
            SQLiteDatabase.openDatabase(live.absolutePath, null, SQLiteDatabase.OPEN_READWRITE).use {
                it.execSQL("UPDATE fixture_rows SET payload='ABCD' WHERE id='id1'")
            }
            assertEquals(expectedLive, logicalDigest(live))
            RandomAccessFile(candidate, "rw").use { file ->
                file.seek(candidate.length() - 1)
                val oldByte = file.readUnsignedByte()
                file.seek(candidate.length() - 1)
                file.writeByte(oldByte xor 1)
                file.fd.sync()
            }
            assertEquals(expectedCandidate.size, candidate.length())
            assertEquals(false, verifyUnderExclusive(live, candidate, expectedLive, expectedCandidate))
        }
    }

    @Test
    fun syntheticDurableMarkersAndTornNamesFailClosedWithoutTouchingRealData() {
        val root = File(context.noBackupFilesDir, "backup_journal_probe_${UUID.randomUUID()}")
        assertTrue(root.mkdir())
        val syntheticContext = object : ContextWrapper(context) {
            override fun getNoBackupFilesDir(): File = root
        }
        try {
            assertTrue(NativeBackupStartupGate.isSafeForDatabaseOrBoot(syntheticContext))
            val shared = NativeBackupStartupGate.acquireDatabaseSession(syntheticContext)
            assertNotNull(shared)
            val journalDir = File(root, "backup_journal")
            assertTrue(journalDir.mkdir())
            val liveJournal = File(journalDir, "restore_journal.json")
            assertTrue(liveJournal.createNewFile())
            // Markers must reject even if a shared token was already granted.
            assertFalse(NativeBackupStartupGate.isSafeForDatabaseOrBoot(syntheticContext))
            assertNull(NativeBackupStartupGate.acquireDatabaseSession(syntheticContext))
            assertTrue(NativeBackupStartupGate.releaseDatabaseSession(shared!!))
            for (markerName in listOf(
                "restore_journal.json", "restore_journal.partial",
                "reconcile_pending.flag", "reconcile_pending.torn",
            )) {
                val marker = File(journalDir, markerName)
                if (!marker.exists()) assertTrue(marker.createNewFile())
                assertFalse("Marker $markerName allowed normal admission",
                    NativeBackupStartupGate.isSafeForDatabaseOrBoot(syntheticContext))
                assertNull("Marker $markerName allowed a database session",
                    NativeBackupStartupGate.acquireDatabaseSession(syntheticContext))
                assertNull("Marker $markerName allowed exclusive owner",
                    NativeBackupStartupGate.withExclusiveFixtureOwnerForTest(syntheticContext) { true })
                assertTrue(marker.delete())
            }
            assertTrue(NativeBackupStartupGate.isSafeForDatabaseOrBoot(syntheticContext))
            assertEquals(true,
                NativeBackupStartupGate.withExclusiveFixtureOwnerForTest(syntheticContext) { true })
        } finally {
            assertTrue("Synthetic marker fixture cleanup failed", root.deleteRecursively())
        }
    }

    @Test
    fun verifierExceptionStillReleasesExclusiveOwner() {
        fixture { _, _ ->
            val result = runCatching {
                NativeBackupStartupGate.withExclusiveFixtureOwnerForTest(context) {
                    throw IllegalStateException("fixture interruption")
                }
            }
            assertTrue(result.isFailure)
            val subsequent = NativeBackupStartupGate.acquireDatabaseSession(context)
            assertNotNull(subsequent)
            assertTrue(NativeBackupStartupGate.releaseDatabaseSession(subsequent!!))
        }
    }
}
