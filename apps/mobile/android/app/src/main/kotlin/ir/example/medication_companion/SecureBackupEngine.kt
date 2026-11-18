package ir.example.medication_companion

import android.app.ActivityManager
import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.database.sqlite.SQLiteDatabase
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
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

    fun export(sourcePath: String, snapshotPath: String, uri: Uri, password: String): Map<String, Any> =
        exportLock.withLock { exportUnlocked(sourcePath, snapshotPath, uri, password) }

    /** Checks space and the trusted live database before Dart creates a
     * consistent, bound VACUUM INTO snapshot through the app's own SQLite FFI.
     * We only return our private no-backup directory, never an SAF URI.
     */
    fun prepareExport(sourcePath: String): String = exportLock.withLock {
        val source = verifiedSource(sourcePath)
        val stagingRoot = File(context.noBackupFilesDir, "backup_staging")
        if (!stagingRoot.isDirectory && !stagingRoot.mkdirs()) {
            throw BackupProblem("فضای امن موقت در دسترس نیست")
        }
        val estimated = (source.length() + File(source.path + "-wal").length())
            .coerceIn(4096L, maxBytes)
        if (context.noBackupFilesDir.usableSpace < estimated * 3 + 16L * 1024 * 1024) {
            throw BackupProblem("فضای داخلی برای ساخت نسخه امن کافی نیست")
        }
        stagingRoot.canonicalPath
    }

    /** Only used for an unconsumed SAF document after an export was cancelled
     * before encryption. Deletes the empty/partial file best-effort. */
    fun discardPendingDocument(uri: Uri) = exportLock.withLock { tryDeletePartial(uri) }

    private fun verifiedSource(sourcePath: String): File {
        val root = context.applicationInfo.dataDir?.let(::File)?.canonicalFile
            ?: throw BackupProblem("پوشه خصوصی برنامه پیدا نشد")
        val source = File(sourcePath).canonicalFile
        if (!source.path.startsWith(root.path + File.separator) || !source.isFile) {
            throw BackupProblem("مسیر پایگاه داده برنامه تأیید نشد")
        }
        return source
    }

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
                File(folder, "import.medbackup.part").delete()
                File(folder, "import.sqlite").delete()
                File(folder, "import.sqlite-wal").delete()
                File(folder, "import.sqlite-shm").delete()
                folder.delete()
            }
        } finally { exportLock.unlock() }
    }

    /** M4-01C, phase A only: authenticate before the untrusted SQLite file is
     * ever opened. The caller MUST inspect the returned quarantined file with
     * a defensive, read-only SQLite connection and invoke clearImport().
     * This method never opens or replaces the application's live database.
     */
    fun decryptImport(uri: Uri, password: String): String = exportLock.withLock {
        requirePassword(password)
        val resolver = context.contentResolver
        val advertisedSize = try {
            resolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else -1L
            } ?: -1L
        } catch (error: Exception) {
            throw BackupProblem("خواندن مشخصات فایل انتخاب‌شده ممکن نشد", error)
        }
        if (advertisedSize == 0L || advertisedSize in 1..4216 ||
            advertisedSize > maxBytes + 121) {
            throw BackupProblem("حجم فایل انتخاب‌شده نامعتبر است")
        }
        val stagingRoot = File(context.noBackupFilesDir, "backup_staging")
        if (!stagingRoot.isDirectory && !stagingRoot.mkdirs()) {
            throw BackupProblem("فضای موقت امن در دسترس نیست")
        }
        val work = File(stagingRoot, UUID.randomUUID().toString())
        if (!work.mkdir()) throw BackupProblem("ساخت پوشه امن ناموفق بود")
        val encrypted = File(work, "import.medbackup.part")
        val decrypted = File(work, "import.sqlite")
        var key: ByteArray? = null
        var pass: ByteArray? = null
        var completed = false
        try {
            if (context.noBackupFilesDir.usableSpace < 2 * maxBytes + 32L * 1024 * 1024) {
                throw BackupProblem("فضای داخلی کافی برای بررسی پشتیبان وجود ندارد")
            }
            val input = resolver.openInputStream(uri)
                ?: throw BackupProblem("فایل انتخاب‌شده قابل خواندن نیست")
            val actual = input.use { source ->
                FileOutputStream(encrypted).use { sink ->
                    val count = copyBounded(source, sink, maxBytes + 121)
                    sink.fd.sync()
                    count
                }
            }
            if (actual !in 4217..(maxBytes + 121) ||
                (advertisedSize > 0 && advertisedSize != actual)) {
                throw BackupProblem("اندازه واقعی فایل با مشخصات آن سازگار نیست")
            }
            // Validate every pre-KDF field without JSON parsing or allocating
            // memory proportional to attacker-controlled input.
            val frame = ByteArray(headerSize)
            FileInputStream(encrypted).use { readExactly(it, frame) }
            val header = ByteBuffer.wrap(frame).order(ByteOrder.BIG_ENDIAN)
            if (!frame.copyOfRange(0, 4).contentEquals(byteArrayOf(0x4d, 0x43, 0x42, 0x4b)) ||
                frame[4].toInt() != 1 || header.getShort(5).toInt() != 90 ||
                !frame.copyOfRange(7, 28).contentEquals(
                    "medication-companion\u0000".toByteArray(Charsets.US_ASCII)) ||
                header.getLong(44) !in 1..8640000000000000L ||
                header.getInt(52) != 5 || frame[56].toInt() != 1 ||
                frame[57].toInt() != 1 || header.getInt(58) != 65536 ||
                header.getInt(62) != 3 || frame[66].toInt() != 1 ||
                header.getShort(95).toInt() != 0 ||
                header.getLong(97) !in 4096..maxBytes ||
                header.getLong(97) + 121 != actual) {
                throw BackupProblem("هدر پشتیبان معتبر نیست")
            }
            pass = password.toByteArray(Charsets.UTF_8)
            key = deriveKey(pass, frame.copyOfRange(67, 83))
            openAuthenticated(encrypted, decrypted, key)
            if (decrypted.length() != header.getLong(97)) {
                throw BackupProblem("اندازه داده بازشده تأیید نشد")
            }
            encrypted.delete()
            completed = true
            return@withLock decrypted.canonicalPath
        } catch (error: Exception) {
            if (error is BackupProblem) throw error
            throw BackupProblem("بررسی فایل پشتیبان ناموفق بود؛ اطلاعات فعلی تغییر نکرد", error)
        } finally {
            key?.let { Arrays.fill(it, 0) }
            pass?.let { Arrays.fill(it, 0) }
            if (!completed) {
                decrypted.delete()
                encrypted.delete()
                work.delete()
            }
        }
    }

    /** Only the exact no_backup/backup_staging/<UUID>/import.sqlite
     * quarantine is accepted. Every deletion is checked and directory-fsynced.
     * Unknown files, symlinks, and permission errors must fail closed.
     */
    fun clearImport(path: String) = exportLock.withLock {
        val root = File(context.noBackupFilesDir, "backup_staging").canonicalFile
        val file = File(path).canonicalFile
        val folder = file.parentFile
        if (file.name != "import.sqlite" || folder?.parentFile != root ||
            folder.name.matches(Regex("[0-9a-fA-F-]{36}")) != true) {
            throw BackupProblem("مسیر فایل موقت تأیید نشد")
        }
        if (!root.isDirectory) throw BackupProblem("پوشه موقت امن موجود نیست")
        // A successful previous cleanup is idempotent, but an unexpected
        // directory entry is not authorization to delete arbitrary files.
        val folderInfo = try {
            Os.lstat(folder.path)
        } catch (error: ErrnoException) {
            if (error.errno == OsConstants.ENOENT) return@withLock
            throw BackupProblem("بررسی پوشه موقت ناموفق بود", error)
        }
        if ((folderInfo.st_mode and OsConstants.S_IFMT) != OsConstants.S_IFDIR) {
            throw BackupProblem("نوع پوشه موقت نامعتبر است")
        }
        val allowed = setOf(
            "import.sqlite", "import.sqlite-wal",
            "import.sqlite-shm", "import.medbackup.part"
        )
        val entries = folder.listFiles()
            ?: throw BackupProblem("فهرست فایل‌های موقت قابل بررسی نیست")
        if (entries.any { it.name !in allowed }) {
            throw BackupProblem("فایل ناشناخته در پوشه موقت؛ پاکسازی متوقف شد")
        }
        for (name in allowed) {
            val target = File(folder, name)
            val info = try {
                Os.lstat(target.path)
            } catch (error: ErrnoException) {
                if (error.errno == OsConstants.ENOENT) null
                else throw BackupProblem("بازرسی فایل موقت ناموفق بود", error)
            }
            if (info != null) {
                if ((info.st_mode and OsConstants.S_IFMT) != OsConstants.S_IFREG) {
                    throw BackupProblem("پیوند یا نوع فایل موقت نامعتبر است")
                }
                try {
                    Os.unlink(target.path)
                } catch (error: ErrnoException) {
                    throw BackupProblem("حذف فایل موقت ناموفق بود", error)
                }
            }
        }
        NativeRestoreJournal.fsyncDirectory(folder)
        Os.rmdir(folder.path)
        NativeRestoreJournal.fsyncDirectory(root)
    }

    private fun exportUnlocked(sourcePath: String, snapshotPath: String, uri: Uri, password: String): Map<String, Any> {
        requirePassword(password)
        verifiedSource(sourcePath)
        val stagingRoot = File(context.noBackupFilesDir, "backup_staging").canonicalFile
        val snapshot = File(snapshotPath).canonicalFile
        val work = snapshot.parentFile
            ?: throw BackupProblem("مسیر تصویر موقت تأیید نشد")
        if (snapshot.name != "snapshot.sqlite" || work.parentFile != stagingRoot ||
            !Regex("[0-9a-fA-F-]{36}").matches(work.name) || !snapshot.isFile) {
            throw BackupProblem("مسیر تصویر موقت تأیید نشد")
        }
        val encrypted = File(work, "export.medbackup.part")
        val verification = File(work, "verify.sqlite")
        var passwordBytes: ByteArray? = null
        try {
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

    /** Debug-only, cross-runtime KAT from libsodium Argon2id13 and OpenSSL AES-GCM.
     * No real data, filesystem access, or deterministic production nonce.
     */
    fun verifyKnownAnswerVector(): Boolean {
        val password = "M4-01 vector فارسی🌷 2026!".toByteArray(Charsets.UTF_8)
        val salt = ByteArray(16) { it.toByte() }
        val nonce = ByteArray(12) { (it + 16).toByte() }
        val key = deriveKey(password, salt)
        try {
            if (!MessageDigest.isEqual(key, hex("ecc6fe38b3878f93ac4e08419b09f4b17658bf02abd7f0da7be61601eb00827f"))) {
                return false
            }
            val prefix = ByteBuffer.allocate(headerSize).order(ByteOrder.BIG_ENDIAN).apply {
                put(byteArrayOf(0x4d, 0x43, 0x42, 0x4b))
                put(1)
                putShort(90)
                put("medication-companion\u0000".toByteArray(Charsets.US_ASCII))
                put(ByteArray(16) { (it + 32).toByte() })
                putLong(1794910000000)
                putInt(5)
                put(1)
                put(1)
                putInt(65536)
                putInt(3)
                put(1)
                put(salt)
                put(nonce)
                putShort(0)
                putLong(4096)
            }.array()
            val payload = ByteArray(4096)
            "SQLite format 3\u0000".toByteArray(Charsets.US_ASCII).copyInto(payload)
            val output = ByteArray(4096 + 32)
            val encryptor = newGcm(true, key, nonce, prefix)
            val chunk = encryptor.processBytes(payload, 0, payload.size, output, 0)
            val finalBytes = encryptor.doFinal(output, chunk)
            val sealed = output.copyOf(chunk + finalBytes)
            val frameHash = MessageDigest.getInstance("SHA-256").digest(prefix + sealed)
            if (!MessageDigest.isEqual(frameHash,
                    hex("6e22ddbca135a55a2ec5e4febfd730c8c94cd17ee7f30138abc7b4c34851106f"))) {
                return false
            }
            val decryptor = newGcm(false, key, nonce, prefix)
            val recovered = ByteArray(4096 + 32)
            val count = decryptor.processBytes(sealed, 0, sealed.size, recovered, 0)
            val tail = decryptor.doFinal(recovered, count)
            return count + tail == payload.size &&
                MessageDigest.isEqual(payload, recovered.copyOf(count + tail))
        } finally {
            Arrays.fill(password, 0)
            Arrays.fill(key, 0)
        }
    }

    private fun hex(value: String): ByteArray = value.chunked(2)
        .map { it.toInt(16).toByte() }.toByteArray()

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
