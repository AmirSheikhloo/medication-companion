package ir.example.medication_companion

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertNull
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import java.io.File
import java.util.UUID
import org.junit.Test
import org.junit.runner.RunWith

/** Exercise the same debug-only SQLite rollback matrix on an actual Android runtime.
 * The sandbox is unique and never touches the application's Drift database.
 */
@RunWith(AndroidJUnit4::class)
class NativeRestoreFaultMatrixInstrumentedTest {
    @Test
    fun quarantineCleanupIsIdempotentAndRejectsUnknownFiles() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val staging = File(context.noBackupFilesDir, "backup_staging")
        assertTrue(staging.isDirectory || staging.mkdirs())
        val engine = SecureBackupEngine(context)
        val folder = File(staging, UUID.randomUUID().toString())
        assertTrue(folder.mkdir())
        val quarantine = File(folder, "import.sqlite")
        quarantine.writeText("SYNTHETIC-ONLY")
        val quarantinePath = quarantine.canonicalPath
        engine.clearImport(quarantinePath)
        assertFalse(quarantine.exists())
        assertFalse(folder.exists())
        engine.clearImport(quarantinePath) // repeat must be harmless

        val unknownFolder = File(staging, UUID.randomUUID().toString())
        assertTrue(unknownFolder.mkdir())
        val unknownFile = File(unknownFolder, "unexpected.file")
        val file = File(unknownFolder, "import.sqlite")
        unknownFile.writeText("DO-NOT-DELETE")
        file.writeText("SYNTHETIC-ONLY")
        try {
            assertTrue(runCatching { engine.clearImport(file.canonicalPath) }.isFailure)
            assertTrue(unknownFile.exists())
            assertTrue(file.exists())
        } finally {
            assertTrue(unknownFile.delete())
            engine.clearImport(file.canonicalPath)
        }
    }

    @Test
    fun rollbackInterruptionsAndFreshInstallStatesAreRecoverable() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val diagnostic = NativeRestoreFaultMatrix.runDiagnostic(context)
        assertNull("M4 rollback matrix failed at: $diagnostic", diagnostic)
    }
}
