package ir.example.medication_companion

import android.app.ActivityManager
import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.database.sqlite.SQLiteDatabase
import org.bouncycastle.crypto.engines.AESEngine
import org.bouncycastle.crypto.generators.Argon2BytesGenerator
import org.bouncycastle.crypto.modes.GCMBlockCipher
import org.bouncycastle.crypto.params.AEADParameters
import org.bouncycastle.crypto.params.Argon2Parameters
import org.bouncycastle.crypto.params.KeyParameter
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.security.SecureRandom
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Arrays
import java.util.UUID
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** M4-01B: Android-only export; never changes or replaces the live SQLite file.
 *
 * AEAD engine is BC lightweight GCMBlockCipher (processBytes emits bounded
 * blocks). Do NOT replace with platform javax.crypto.Cipher, whose Android
 * Conscrypt GCM provider may buffer the entire input. Native allocation,
 * cross-runtime interoperability and 64 MiB RSS remain DEVICE release gates.
 */
internal class SecureBackupEngine(private val context: Context) {
    companion object { private val exportLock = ReentrantLock() }
    private val rng = SecureRandom()
    private val chunkSize = 64 * 1024
    private val maxBytes = 64L * 1024 * 1024
    private val headerSize = 105
    private val tables = listOf(
        "profiles", "app_settings", "medications", "medication_plan_versions",
        "dose_events", "dose_current_states", "stock_packages", "stock_selections",
        "stock_movements", "stock_alert_rules", "health_measurements",
        "health_measurement_versions", "care_visits", "care_tasks",
        "care_task_events", "visit_checklist_items", "visit_questions"
    )

    fun export(sourcePath: String, uri: Uri, password: String): Map<String, Any> =
        exportLock.withLock { exportUnlocked(sourcePath, uri, password) }

    /** Cold-launch cleanup only. A future restore journal always takes priority. */
    fun sweepAbandonedExportStaging() {
        if (!exportLock.tryLock()) return
        try {
            val journal = File(context.noBackupFilesDir, "backup_journal")
            if (File(journal, "restore_journal.json").exists() ||
                File(journal, "reconcile_pending.flag").exists()) return
            val staging = File(context.noBackupFilesDir, "backup_staging")
            for (folder in staging.listFiles().orEmpty()) {
                if (!folder.isDirectory ||
                    !Regex("[0-9a-fA-F-]{36}").matches(folder.name)) continue
                File(folder, "snapshot.sqlite").delete()
                File(folder, "verify.sqlite").delete()
                File(folder, "export.medbackup.part").delete()
                folder.delete()
            }
        } finally { exportLock.unlock() }
    }

    private fun exportUnlocked(sourcePath: String, uri: Uri, password: String): Map<String, Any> {
        requirePassword(password)
        val root = context.applicationInfo.dataDir?.let(::File)?.canonicalFile
            ?: throw BackupProblem("پوشه خصوصی برنامه پیدا نشد")
        val source = File(sourcePath).canonicalFile
        if (!source.path.startsWith(root.path + File.separator) || !source.isFile) {
            throw BackupProblem("مسیر پایگاه داده برنامه تأیید نشد")
        }
        val stagingRoot = File(context.noBackupFilesDir, "backup_staging")
        if (!stagingRoot.isDirectory && !stagingRoot.mkdirs()) {
            throw BackupProblem("فضای امن موقت در دسترس نیست")
        }
        val work = File(stagingRoot, UUID.randomUUID().toString())
        if (!work.mkdir()) throw BackupProblem("ساخت پوشه موقت ناموفق بود")
        val snapshot = File(work, "snapshot.sqlite")
        val encrypted = File(work, "export.medbackup.part")
        val verification = File(work, "verify.sqlite")
        var passwordBytes: ByteArray? = null
        try {
            // Worst-case allowance covers snapshot, envelope, verification and margin.
            // Refuse before VACUUM rather than filling internal storage.
            val expected = (source.length() + File(source.path + "-wal").length())
                .coerceIn(4096, maxBytes)
            if (context.noBackupFilesDir.usableSpace < expected * 3 + 16L * 1024 * 1024) {
                throw BackupProblem("فضای داخلی برای ساخت نسخه امن کافی نیست")
            }

            createConsistentSnapshot(source, snapshot)
            val snapshotLength = snapshot.length()
            if (snapshotLength !in 4096..maxBytes) {
                throw BackupProblem("حجم پایگاه داده از سقف ۶۴ مگابایت خارج است")
            }
            val originalCounts = inspectSnapshot(snapshot)
            passwordBytes = password.toByteArray(Charsets.UTF_8)
            val salt = ByteArray(16).also(rng::nextBytes)
            val nonce = ByteArray(12).also(rng::nextBytes)
            val prefix = buildPrefix(snapshotLength, salt, nonce)
            val key = deriveKey(passwordBytes, salt)
            try {
                seal(snapshot, encrypted, prefix, key, nonce)
            } finally {
                Arrays.fill(key, 0)
            }
            if (encrypted.length() != snapshotLength + 121) {
                throw BackupProblem("اندازه فایل رمزگذاری‌شده نامعتبر است")
            }

            // Independently derive the key again and authenticate the exact
            // published frame before parsing any decrypted SQLite bytes.
            val secondKey = deriveKey(passwordBytes, salt)
            try {
                openAuthenticated(encrypted, verification, secondKey)
            } finally {
                Arrays.fill(secondKey, 0)
            }
            if (verification.length() != snapshotLength || inspectSnapshot(verification) != originalCounts) {
                throw BackupProblem("راستی‌آزمایی پشتیبان موفق نبود")
            }
            // No plaintext remains needed past this point.
            verification.delete()
            snapshot.delete()

            val status = publishToSaf(uri, encrypted)
            return mapOf(
                "verified" to status,
                "bytes" to encrypted.length(),
                "createdAt" to System.currentTimeMillis()
            )
        } catch (error: Exception) {
            // ACTION_CREATE_DOCUMENT may already have created an empty file.
            // The encrypted data is never published until local verification.
            tryDeletePartial(uri)
            throw error
        } finally {
            passwordBytes?.let { Arrays.fill(it, 0) }
            verification.delete()
            snapshot.delete()
            encrypted.delete()
            work.delete()
        }
    }

    private fun requirePassword(password: String) {
        if (password.codePointCount(0, password.length) < 12 || password.isBlank()) {
            throw BackupProblem("رمز باید دست‌کم ۱۲ نویسه داشته باشد")
        }
        var i = 0
        while (i < password.length) {
            val c = password[i]
            if (Character.isHighSurrogate(c)) {
                if (i + 1 >= password.length || !Character.isLowSurrogate(password[i + 1])) {
                    throw BackupProblem("رمز شامل نویسه نامعتبر است")
                }
                i += 2
            } else {
                if (Character.isLowSurrogate(c)) throw BackupProblem("رمز شامل نویسه نامعتبر است")
                i++
            }
        }
    }

    private fun createConsistentSnapshot(source: File, target: File) {
        val connection = SQLiteDatabase.openDatabase(source.path, null, SQLiteDatabase.OPEN_READONLY)
        try {
            connection.execSQL("PRAGMA busy_timeout=5000")
            // Parameter bound; no interpolation of paths or active DB copies.
            connection.execSQL("VACUUM INTO ?", arrayOf(target.absolutePath))
        } catch (error: Exception) {
            throw BackupProblem("گرفتن تصویر یکپارچه دیتابیس ناموفق بود", error)
        } finally {
            connection.close()
        }
    }

    private fun inspectSnapshot(path: File): List<Long> {
        val db = SQLiteDatabase.openDatabase(path.path, null, SQLiteDatabase.OPEN_READONLY)
        try {
            val integrity = db.rawQuery("PRAGMA integrity_check(10)", null)
            integrity.use {
                if (!it.moveToFirst() || it.getString(0) != "ok" || it.moveToNext()) {
                    throw BackupProblem("یکپارچگی دیتابیس تأیید نشد")
                }
            }
            db.rawQuery("PRAGMA foreign_key_check", null).use {
                if (it.moveToFirst()) throw BackupProblem("ارجاع داده‌ها ناسازگار است")
            }
            db.rawQuery("PRAGMA user_version", null).use {
                if (!it.moveToFirst() || it.getInt(0) != 5) {
                    throw BackupProblem("نسخه پایگاه داده قابل پشتیبانی نیست")
                }
            }
            val counts = ArrayList<Long>()
            for (table in tables) {
                // Fixed compile-time whitelist: no untrusted identifier interpolation.
                db.rawQuery("SELECT COUNT(*) FROM \"$table\"", null).use {
                    if (!it.moveToFirst()) throw BackupProblem("جدول مورد انتظار موجود نیست")
                    counts.add(it.getLong(0))
                }
            }
            return counts
        } finally {
            db.close()
        }
    }

    private fun buildPrefix(size: Long, salt: ByteArray, nonce: ByteArray): ByteArray {
        val out = ByteBuffer.allocate(headerSize).order(ByteOrder.BIG_ENDIAN)
        out.put(byteArrayOf(0x4d, 0x43, 0x42, 0x4b))
        out.put(1)
        out.putShort(90)
        out.put("medication-companion\u0000".toByteArray(Charsets.US_ASCII))
        out.put(ByteArray(16).also(rng::nextBytes))
        out.putLong(System.currentTimeMillis())
        out.putInt(5)
        out.put(1)
        out.put(1)
        out.putInt(65536)
        out.putInt(3)
        out.put(1)
        out.put(salt)
        out.put(nonce)
        out.putShort(0)
        out.putLong(size)
        check(out.position() == headerSize)
        return out.array()
    }

    private fun deriveKey(passwordBytes: ByteArray, salt: ByteArray): ByteArray {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memory = ActivityManager.MemoryInfo()
        am.getMemoryInfo(memory)
        if (memory.lowMemory || memory.availMem < 160L * 1024 * 1024) {
            throw BackupProblem("حافظه رم دستگاه برای پشتیبان‌گیری کافی نیست")
        }
        val params = Argon2Parameters.Builder(Argon2Parameters.ARGON2_id)
            .withVersion(Argon2Parameters.ARGON2_VERSION_13)
            .withSalt(salt)
            .withMemoryAsKB(65536)
            .withIterations(3)
            .withParallelism(1)
            .build()
        val out = ByteArray(32)
        try {
            Argon2BytesGenerator().apply { init(params) }.generateBytes(passwordBytes, out)
            return out
        } catch (error: OutOfMemoryError) {
            Arrays.fill(out, 0)
            throw BackupProblem("حافظه برای اجرای رمزگذاری کافی نیست", error)
        } finally {
            params.clear()
        }
    }

    private fun newGcm(encrypting: Boolean, key: ByteArray, nonce: ByteArray, aad: ByteArray): GCMBlockCipher {
        val cipher = GCMBlockCipher(AESEngine())
        cipher.init(encrypting, AEADParameters(KeyParameter(key), 128, nonce, aad))
        return cipher
    }

    private fun seal(snapshot: File, target: File, prefix: ByteArray, key: ByteArray, nonce: ByteArray) {
        val cipher = newGcm(true, key, nonce, prefix)
        val input = ByteArray(chunkSize)
        val output = ByteArray(chunkSize + 32)
        try {
            FileInputStream(snapshot).use { source ->
                FileOutputStream(target).use { sink ->
                    sink.write(prefix)
                    while (true) {
                        val read = source.read(input)
                        if (read < 0) break
                        val count = cipher.processBytes(input, 0, read, output, 0)
                        if (count > 0) sink.write(output, 0, count)
                    }
                    val finalCount = cipher.doFinal(output, 0)
                    sink.write(output, 0, finalCount)
                    sink.fd.sync()
                }
            }
        } finally {
            Arrays.fill(input, 0)
            Arrays.fill(output, 0)
            cipher.reset()
        }
    }

    private fun openAuthenticated(encrypted: File, target: File, key: ByteArray) {
        val frame = ByteArray(headerSize)
        val input = ByteArray(chunkSize)
        val output = ByteArray(chunkSize + 32)
        try {
            FileInputStream(encrypted).use { source ->
                readExactly(source, frame)
                val header = ByteBuffer.wrap(frame).order(ByteOrder.BIG_ENDIAN)
                val magic = ByteArray(4).also { header.get(it) }
                if (!magic.contentEquals(byteArrayOf(0x4d, 0x43, 0x42, 0x4b)) ||
                    header.get().toInt() != 1 || header.short.toInt() != 90) {
                    throw BackupProblem("قالب فایل رمزگذاری‌شده نامعتبر است")
                }
                val app = ByteArray(21).also { header.get(it) }
                if (!app.contentEquals("medication-companion\u0000".toByteArray(Charsets.US_ASCII))) {
                    throw BackupProblem("شناسه برنامه نامعتبر است")
                }
                header.position(44)
                val time = header.long
                val version = header.int
                val cipherId = header.get().toInt()
                val kdfId = header.get().toInt()
                val memory = header.int
                val iterations = header.int
                val parallelism = header.get().toInt()
                header.position(83)
                val nonce = ByteArray(12).also { header.get(it) }
                val reserved = header.short
                val size = header.long
                if (time !in 1..8640000000000000L || version != 5 || cipherId != 1 ||
                    kdfId != 1 || memory != 65536 || iterations != 3 || parallelism != 1 ||
                    reserved.toInt() != 0 || size !in 4096..maxBytes ||
                    encrypted.length() != 121 + size) {
                    throw BackupProblem("پارامترهای فایل پشتیبان نامعتبر است")
                }
                val cipher = newGcm(false, key, nonce, frame)
                try {
                    FileOutputStream(target).use { sink ->
                        var remaining = size + 16
                        while (remaining > 0) {
                            val read = source.read(input, 0, minOf(chunkSize.toLong(), remaining).toInt())
                            if (read <= 0) throw BackupProblem("فایل رمزگذاری‌شده ناقص است")
                            remaining -= read
                            val count = cipher.processBytes(input, 0, read, output, 0)
                            if (count > 0) sink.write(output, 0, count)
                        }
                        val finalCount = cipher.doFinal(output, 0)
                        if (finalCount > 0) sink.write(output, 0, finalCount)
                        sink.fd.sync()
                    }
                } catch (error: Exception) {
                    target.delete() // no unverified plaintext may reach SQLite
                    throw BackupProblem("تأیید اصالت رمزنگاری ناموفق بود", error)
                } finally {
                    cipher.reset()
                }
            }
        } finally {
            Arrays.fill(input, 0)
            Arrays.fill(output, 0)
        }
    }

    private fun readExactly(source: InputStream, bytes: ByteArray) {
        var offset = 0
        while (offset < bytes.size) {
            val count = source.read(bytes, offset, bytes.size - offset)
            if (count <= 0) throw BackupProblem("خواندن فایل پشتیبان ناقص بود")
            offset += count
        }
    }

    /** Returns true ONLY if the destination can be re-opened and SHA-256 matched. */
    private fun publishToSaf(uri: Uri, encrypted: File): Boolean {
        val resolver = context.contentResolver
        var wroteBytes = 0L
        try {
            val pfd: ParcelFileDescriptor? = try {
                resolver.openFileDescriptor(uri, "wt")
            } catch (_: Exception) {
                null // Some cloud providers expose only stream endpoints.
            }
            if (pfd != null) {
                var stream: ParcelFileDescriptor.AutoCloseOutputStream? = null
                var success = false
                try {
                    val sink = ParcelFileDescriptor.AutoCloseOutputStream(pfd)
                    stream = sink
                    FileInputStream(encrypted).use { source ->
                        wroteBytes = copyBounded(source, sink, encrypted.length())
                    }
                    sink.flush()
                    try { sink.fd.sync() } catch (_: Exception) { /* remote pipe */ }
                    sink.close() // AutoCloseOutputStream uniquely owns the PFD
                    success = true
                } catch (error: Exception) {
                    try { pfd.closeWithError("incomplete backup") } catch (_: Exception) {}
                    throw error
                } finally {
                    if (!success) try { stream?.close() ?: pfd.close() } catch (_: Exception) {}
                }
            } else {
                val stream = try { resolver.openOutputStream(uri, "wt") }
                catch (_: Exception) { resolver.openOutputStream(uri) }
                    ?: throw BackupProblem("محل ذخیره اجازه نوشتن نمی‌دهد")
                stream.use { sink ->
                    FileInputStream(encrypted).use { source ->
                        wroteBytes = copyBounded(source, sink, encrypted.length())
                    }
                    sink.flush()
                }
            }
            if (wroteBytes != encrypted.length()) {
                throw BackupProblem("فایل پشتیبان ناقص نوشته شد")
            }
            val expected = digest(FileInputStream(encrypted))
            val actual = try {
                resolver.openInputStream(uri)?.use(::digest)
            } catch (_: Exception) { null }
            if (actual == null) return false // no false claim of SAF verification
            if (!MessageDigest.isEqual(expected.hash, actual.hash) || expected.count != actual.count) {
                throw BackupProblem("فایل مقصد با نسخه رمزگذاری‌شده تفاوت دارد")
            }
            return true
        } catch (error: Exception) {
            tryDeletePartial(uri)
            if (error is BackupProblem) throw error
            throw BackupProblem("ذخیره فایل پشتیبان ناموفق بود؛ احتمال باقی‌ماندن فایل ناقص وجود دارد", error)
        }
    }

    private fun copyBounded(source: InputStream, sink: java.io.OutputStream, size: Long): Long {
        val bytes = ByteArray(chunkSize)
        var copied = 0L
        try {
            while (true) {
                val count = source.read(bytes)
                if (count < 0) break
                copied += count
                if (copied > size) throw BackupProblem("داده بیشتر از اندازه مجاز است")
                sink.write(bytes, 0, count)
            }
            return copied
        } finally { Arrays.fill(bytes, 0) }
    }

    private data class Digest(val hash: ByteArray, val count: Long)
    private fun digest(input: InputStream): Digest {
        input.use { source ->
            val md = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(chunkSize)
            var readTotal = 0L
            try {
                while (true) {
                    val count = source.read(buffer)
                    if (count < 0) break
                    readTotal += count
                    if (readTotal > maxBytes + 121) {
                        throw BackupProblem("اندازه فایل مقصد غیرمجاز است")
                    }
                    md.update(buffer, 0, count)
                }
                return Digest(md.digest(), readTotal)
            } finally { Arrays.fill(buffer, 0) }
        }
    }

    private fun tryDeletePartial(uri: Uri) {
        if (!DocumentsContract.isDocumentUri(context, uri)) return
        try {
            val projection = arrayOf(DocumentsContract.Document.COLUMN_FLAGS)
            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst() &&
                    cursor.getInt(0) and DocumentsContract.Document.FLAG_SUPPORTS_DELETE != 0) {
                    DocumentsContract.deleteDocument(context.contentResolver, uri)
                }
            }
        } catch (_: Exception) { /* best effort only */ }
    }
}

internal class BackupProblem(message: String, cause: Throwable? = null) : Exception(message, cause)
