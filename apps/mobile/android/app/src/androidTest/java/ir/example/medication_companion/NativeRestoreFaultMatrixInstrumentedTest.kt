package ir.example.medication_companion

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
    fun allFourRollbackInterruptionsAreRecoverable() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val diagnostic = NativeRestoreFaultMatrix.runDiagnostic(context)
        assertNull("M4 rollback matrix failed at: $diagnostic", diagnostic)
    }
}
