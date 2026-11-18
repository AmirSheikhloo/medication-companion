package ir.example.medication_companion

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.net.Uri
import android.content.pm.ApplicationInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val requestCreateDocument = 9321
    private val requestOpenDocument = 9322
    private val worker = Executors.newSingleThreadExecutor()
    private val ui = Handler(Looper.getMainLooper())
    private var pendingPicker: MethodChannel.Result? = null
    private var selectedDestination: Uri? = null
    private var selectedImport: Uri? = null
    private var exporting = false
    private var importing = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "medication_companion/secure_backup")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bootstrapRecovery" -> {
                        worker.execute {
                            val safe = NativeBackupStartupGate.isSafeForDatabaseOrBoot(applicationContext)
                            if (safe) {
                                SecureBackupEngine(applicationContext).sweepAbandonedExportStaging()
                            }
                            ui.post { result.success(safe) }
                        }
                    }
                    "acquireDatabaseLease" -> {
                        worker.execute {
                            val token = NativeBackupStartupGate.acquireDatabaseSession(applicationContext)
                            ui.post { result.success(token) }
                        }
                    }
                    "releaseDatabaseLease" -> {
                        val token = call.argument<String>("token")
                        if (token.isNullOrBlank()) {
                            result.error("INVALID", "شناسهٔ قفل پایگاه داده معتبر نیست", null)
                        } else {
                            worker.execute {
                                val released = NativeBackupStartupGate.releaseDatabaseSession(token)
                                ui.post { result.success(released) }
                            }
                        }
                    }
                    "testNativeLockExclusion" -> {
                        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0 ||
                            exporting || importing || pendingPicker != null) {
                            result.error("DISABLED", "تست قفل فقط در نسخهٔ آزمایشی و حالت بیکار مجاز است", null)
                        } else {
                            worker.execute {
                                val valid = try {
                                    NativeBackupStartupGate.testLockExclusion(applicationContext)
                                } catch (_: Throwable) { false }
                                ui.post { result.success(valid) }
                            }
                        }
                    }
                    "testNativeJournalDurability" -> {
                        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0 ||
                            exporting || importing || pendingPicker != null) {
                            result.error("DISABLED", "آزمون ژورنال فقط در نسخهٔ آزمایشی و حالت بیکار مجاز است", null)
                        } else {
                            worker.execute {
                                val valid = try {
                                    NativeRestoreJournal.debugDurabilityProbe(applicationContext)
                                } catch (_: Throwable) { false }
                                ui.post { result.success(valid) }
                            }
                        }
                    }
                    "testNativeRollbackFaultMatrix" -> {
                        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0 ||
                            exporting || importing || pendingPicker != null) {
                            result.error("DISABLED", "آزمون ضدکرش فقط در نسخهٔ آزمایشی و حالت بیکار مجاز است", null)
                        } else {
                            worker.execute {
                                val valid = try {
                                    NativeRestoreFaultMatrix.run(applicationContext)
                                } catch (_: Throwable) { false }
                                ui.post { result.success(valid) }
                            }
                        }
                    }
                    "testCryptoProvider" -> {
                        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0 || exporting) {
                            result.error("DISABLED", "تست رمزنگاری فقط در نسخه آزمایشی فعال است", null)
                        } else {
                            worker.execute {
                                val valid = try {
                                    SecureBackupEngine(applicationContext).verifyKnownAnswerVector()
                                } catch (_: Throwable) { false }
                                ui.post { result.success(valid) }
                            }
                        }
                    }
                    "chooseDestination" -> {
                        if (pendingPicker != null || exporting || importing) {
                            result.error("BUSY", "یک پشتیبان دیگر در حال انجام است", null)
                        } else {
                            selectedDestination = null
                            pendingPicker = result
                            val filename = call.argument<String>("filename")
                                ?: "medication-backup.medbackup"
                            try {
                                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "application/octet-stream"
                                    putExtra(Intent.EXTRA_TITLE, filename)
                                }
                                startActivityForResult(intent, requestCreateDocument)
                            } catch (error: Exception) {
                                pendingPicker = null
                                result.error("PICKER", "انتخاب محل ذخیره ممکن نشد", null)
                            }
                        }
                    }
                    "export" -> {
                        val uri = selectedDestination
                        val path = call.argument<String>("databasePath")
                        val snapshotPath = call.argument<String>("snapshotPath")
                        val password = call.argument<String>("password")
                        if (exporting || importing || uri == null || path.isNullOrBlank() ||
                            snapshotPath.isNullOrBlank() || password == null) {
                            result.error("INVALID", "درخواست پشتیبان نامعتبر است", null)
                        } else {
                            exporting = true
                            selectedDestination = null // consume one picker result exactly once
                            worker.execute {
                                try {
                                    val output = SecureBackupEngine(applicationContext).export(path, snapshotPath, uri, password)
                                    ui.post {
                                        exporting = false
                                        result.success(output)
                                    }
                                } catch (error: Throwable) {
                                    val message = if (error is BackupProblem) error.message
                                        else "ساخت پشتیبان ناموفق بود؛ اطلاعات فعلی شما تغییر نکرد"
                                    ui.post {
                                        exporting = false
                                        result.error("EXPORT_FAILED", message, null)
                                    }
                                }
                            }
                        }
                    }
                    "prepareExport" -> {
                        val path = call.argument<String>("databasePath")
                        if (exporting || importing || selectedDestination == null || path.isNullOrBlank()) {
                            result.error("INVALID", "درخواست آماده‌سازی پشتیبان نامعتبر است", null)
                        } else {
                            worker.execute {
                                try {
                                    val root = SecureBackupEngine(applicationContext).prepareExport(path)
                                    ui.post { result.success(root) }
                                } catch (error: Exception) {
                                    val message = if (error is BackupProblem) error.message
                                        else "فضای امن برای پشتیبان در دسترس نیست"
                                    ui.post { result.error("PREPARE_FAILED", message, null) }
                                }
                            }
                        }
                    }
                    "discardDestination" -> {
                        val uri = selectedDestination
                        selectedDestination = null
                        if (uri == null) {
                            result.success(true)
                        } else {
                            worker.execute {
                                SecureBackupEngine(applicationContext).discardPendingDocument(uri)
                                ui.post { result.success(true) }
                            }
                        }
                    }
                    "chooseImport" -> {
                        if (pendingPicker != null || exporting || importing) {
                            result.error("BUSY", "عملیات دیگری در حال انجام است", null)
                        } else {
                            selectedImport = null
                            pendingPicker = result
                            try {
                                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "*/*"
                                }
                                startActivityForResult(intent, requestOpenDocument)
                            } catch (_: Exception) {
                                pendingPicker = null
                                result.error("PICKER", "انتخاب فایل ممکن نشد", null)
                            }
                        }
                    }
                    "decryptImport" -> {
                        val uri = selectedImport
                        val password = call.argument<String>("password")
                        if (importing || exporting || uri == null || password == null) {
                            result.error("INVALID", "فایل یا رمز پشتیبان مشخص نیست", null)
                        } else {
                            selectedImport = null
                            importing = true
                            worker.execute {
                                try {
                                    val path = SecureBackupEngine(applicationContext).decryptImport(uri, password)
                                    ui.post {
                                        importing = false
                                        result.success(path)
                                    }
                                } catch (error: Throwable) {
                                    val message = if (error is BackupProblem) error.message
                                        else "بررسی فایل ناموفق بود؛ هیچ اطلاعاتی تغییر نکرد"
                                    ui.post {
                                        importing = false
                                        result.error("IMPORT_FAILED", message, null)
                                    }
                                }
                            }
                        }
                    }
                    "clearImport" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID", "مسیر فایل موقت مشخص نیست", null)
                        } else {
                            worker.execute {
                                try {
                                    SecureBackupEngine(applicationContext).clearImport(path)
                                    ui.post { result.success(true) }
                                } catch (_: Exception) {
                                    ui.post { result.error("CLEANUP", "پاکسازی فایل موقت تأیید نشد", null) }
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != requestCreateDocument && requestCode != requestOpenDocument) return
        val callback = pendingPicker ?: return
        pendingPicker = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (requestCode == requestCreateDocument) selectedDestination = uri
        else selectedImport = uri
        callback.success(uri != null)
    }

    override fun onDestroy() {
        pendingPicker?.error("CANCELLED", "انتخاب فایل متوقف شد", null)
        pendingPicker = null
        selectedDestination = null
        selectedImport = null
        worker.shutdown()
        super.onDestroy()
    }
}
