package ir.example.medication_companion

import android.net.Uri
import android.os.Process
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/** Exercise the same debug-only SQLite rollback matrix on an actual Android runtime.
 * The sandbox is unique and never touches the application's Drift database.
 */
@RunWith(AndroidJUnit4::class)
class NativeRestoreFaultMatrixInstrumentedTest {
    @Test
    fun isolatedProviderReallyDiesAndFreshProcessRecoversDurableJournal() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val uri = Uri.parse("content://" + context.packageName + ".m4killprobe")
        val resolver = context.contentResolver

        for (checkpoint in listOf("OLD_SAVED", "NEW_INSTALLED")) {
            val id = UUID.randomUUID().toString()
            val originalPid = resolver.call(uri, "pid", null, null)?.getInt("pid", -1) ?: -1
            assertTrue("isolated provider must have its own process", originalPid > 0)
            assertNotEquals("provider must not run in instrumentation process",
                Process.myPid(), originalPid)

            // The provider persists a canonical SQLite journal and fixture,
            // then uses android.os.Process.killProcess(myPid()) before reply.
            // A binder exception/null reply is expected and never interpreted
            // as proof of safety by itself.
            runCatching { resolver.call(uri, "kill_" + checkpoint, id, null) }

            var result: android.os.Bundle? = null
            var lastFailure: Throwable? = null
            for (attempt in 1..12) {
                try {
                    result = resolver.call(uri, "recover_" + checkpoint, id, null)
                    if (result != null) break
                } catch (failure: RuntimeException) {
                    lastFailure = failure
                }
                Thread.sleep(200)
            }
            if (result == null) {
                throw AssertionError("isolated provider never restarted: " + checkpoint, lastFailure)
            }
            assertNotEquals("provider did not restart in a new process",
                originalPid, result.getInt("pid", -1))
            assertEquals("incorrect durable state after " + checkpoint,
                if (checkpoint == "OLD_SAVED") "ROLLED_BACK" else "COMMITTED",
                result.getString("terminal"))
            assertTrue("recovery failed for " + checkpoint, result.getBoolean("ok", false))
            val cleaned = resolver.call(uri, "cleanup", id, null)
            assertTrue("isolated sandbox cleanup failed", cleaned?.getBoolean("ok") == true)
        }
    }

    @Test
    fun rollbackInterruptionsAndFreshInstallStatesAreRecoverable() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val diagnostic = NativeRestoreFaultMatrix.runDiagnostic(context)
        assertNull("M4 rollback matrix failed at: $diagnostic", diagnostic)
    }
}
