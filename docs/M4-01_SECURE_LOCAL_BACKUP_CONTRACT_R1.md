# Medication Companion — M4-01 Secure Local Backup & Restore Contract (R1)

**Status:** SECURITY REVIEW CANDIDATE — NOT APPROVED FOR IMPLEMENTATION.
**Project:** `AmirSheikhloo/medication-companion` (independent of Clinic Ecosystem).
**Baseline:** `main` at `4712d2d` (M3-04 merged, Flutter tests and Android debug APK green; manual M3-04 5/5 passed).
**Authoritative product scope:** `Medication_Health_App_PRD_v1.0_RC_FA.md`, especially §§7.1–7.2, 8.3, 11.3, roadmap M4 and edge case E-14.

## 1. Outcome and non-negotiable invariants

Deliver offline, password-protected backup and **explicit full-device-data replacement** restore for all local user profiles, medication plans, events, stock-ledger history, health observations, follow-up visits/tasks, questions, and app settings.

1. **No account, internet, backend, or subscription required.** Backup and restore work with airplane mode enabled.
2. **No silent deletion or overwrite.** Failed/cancelled/incorrect-password/incompatible/corrupted restore causes zero mutations to the active database and scheduled reminders.
3. **No merge in v1.** Restore replaces the entire local dataset only after explicit confirmation showing its effects; preserve primary keys/event history. Future merge requires a separate conflict/idempotency design.
4. **No plaintext backup in shared/public storage.** Share/export only authenticated ciphertext. Any transient unencrypted snapshot stays in app-private storage for minimum time and is removed on success/failure.
5. **Do not claim the existing SQLite database is encrypted.** Current `AppDatabase()` uses `driftDatabase(name: 'medication_companion_m1')`, schema version **5**, without demonstrated SQLCipher-at-rest protection. Encrypted export does not fix that separate privacy gap.
6. **No medical interpretations, dose edits, or inferred data.** This package only reproduces stored user data and reschedules existing local reminders after success.
7. Preserve user data across software upgrades and database migrations. Reject unsupported future backup/schema versions with an explicit explanation, never silently downgrade.
8. Warn accurately: without a backed-up file or online sync, guest data can be irretrievably lost on app uninstall/device loss. Forgotten backup password cannot be recovered by the developer.

## 2. Existing state and exact scope boundary

- Flutter/Drift SQLite file via `AppDatabase()`; **schemaVersion = 5**, onUpgrade paths 1→5; `AppDatabase.forTesting` supports executor injection.
- App data tables include Profiles, AppSettings, Medications, MedicationPlanVersions, DoseEvents, DoseCurrentStates, StockPackages, StockSelections, StockMovements, StockAlertRules, HealthMeasurements, HealthMeasurementVersions, CareVisits, CareTasks, CareTaskEvents, VisitChecklistItems, VisitQuestions (verify authoritative table list in `lib/core/storage/app_database.dart` before implementation).
- Active medication and care reminders use separate, managed Android notification ID ranges. They are derived state: do **not** export OS pending notifications. After accepted restore, recalculate using current notification permissions/time zone.
- No demonstrated user image/attachment storage in current schema. Backup v1 covers the SQLite database only. Clearly state this limitation; future image support must extend the payload format before claiming full backup.
- PRD M4 also mentions online accounts/secure admin panel. **Out of scope here**: registration/OTP, cloud backups, multi-device merge, payments, family permissions, remote admin panel and encryption of the on-device live database. Create later separately gated milestones.

## 3. Threat model and choices

Threats in scope: stolen/exported `.medbackup` file, wrong password, offline password guessing, tampered/truncated/replayed input, attacker-controlled length/KDF fields, huge file/zip bomb, mid-restore crash, low disk space, stale notification jobs, old schema, accidental overwrite of a different profile.

Out of scope: compromised/rooted Android/OS, malicious keyboard, screen recording, a weak password chosen by the user, recovery of a forgotten password. The app must not promise protection against these.

- Encryption: **AES-256-GCM** with 12-byte fresh cryptographically random nonce and 16-byte authentication tag.
- Cross-device password KDF: **Argon2id**, target `memory=64 MiB`, `iterations=3`, `parallelism=1`, `output=32 bytes`, fresh 16-byte random salt per export; benchmark on minimum supported Android device before acceptance. Parameter identifiers are recorded in an authenticated header. Verify minimum against OWASP and profile device performance; any fallback or parameter change requires new encoded KDF parameters and explicit security review. Never silently lower the work factor.
- Password entry: at least 12 characters, double-entry on export, mask/reveal action, no implicit trimming/Unicode normalization, no hardcoded/default password, no persist/log/analytics for password, derived key, or plaintext medical data. Warn user that a strong passphrase is essential and unrecoverable if lost.
- Crypto implementation candidate: `cryptography`/`cryptography_flutter` (audited public APIs for Argon2id/AES-GCM). No custom AES/Argon implementation, `Random()` salts, fixed IVs, homemade XOR, or reversible password storage.
- Device Keystore key is **not** used as the sole backup key because backups must be recoverable on a replacement device. Keystore-based encryption of the *live* DB is a separate design.

## 4. Binary file format: `MCBK v1` (exact contract, independent of SQLite version)

Do not use a plain `.db` or rename a database file to pretend it is encrypted.

```
byte[4]   ASCII "MCBK"
uint8     envelope_version = 1
uint16BE  header_length (bounded, <= 4096)
byte[n]   canonical UTF-8 JSON header; keys sorted, no whitespace variation
uint64BE  ciphertext_length (bounded, v1 max 64 MiB)
byte[m]   AES-GCM ciphertext of payload
byte[16]  AES-GCM tag
EOF       no trailing bytes
```

Header keys, exactly: `app_id="medication-companion"`, `backup_id` (random 128-bit hex), `cipher="AES-256-GCM"`, `created_utc` (ISO 8601), `database_schema=5`, `kdf="argon2id"`, `kdf_memory_kib=65536`, `kdf_iterations=3`, `kdf_parallelism=1`, `salt_b64url` (16 bytes), `nonce_b64url` (12 bytes).

- AES-GCM **AAD** is the exact raw sequence `magic || envelope_version || uint16BE(header_length) || header_bytes || uint64BE(ciphertext_length)` — never reconstruct it from a parsed map. Mutating any header field or declared length must fail authentication.
- Header contains no names, drug lists, phone numbers or plaintext health data; `created_utc` and schema version are intentionally visible metadata.
- Before costly KDF: verify magic, version, size, complete frame length, header character constraints/duplicate keys, allowed algorithm identifiers, bounded Argon2 parameters (defend against malicious memory/CPU values), unique nonce/salt encoding length, unsupported future schema.
- The payload is a single, consistent SQLite database snapshot with SQLite `user_version=5`. GCM integrity **and** SQLite integrity/foreign-key checks are required; one does not replace the other.
- New format/algorithm/schema transitions require explicit versioned readers, known test vectors and migration tests; unknown critical fields cause rejection.

## 5. Export pipeline (no live-data mutation)

1. On `بیشتر → پشتیبان و بازیابی → ساخت پشتیبان رمزگذاری‌شده`, explain data sensitivity, scope, and unrecoverable password. User enters/confirms password and chooses destination with Android Storage Access Framework (SAF) `ACTION_CREATE_DOCUMENT` or supported equivalent.
2. Serialize export access with other snapshot/restore actions. Build a **consistent SQLite snapshot** using SQLite's online backup API or `VACUUM INTO` on an isolated, verified connection. Never copy a live `*.db` file directly while WAL is active. Do not execute `VACUUM INTO` inside an active SQL transaction.
3. Verify snapshot `PRAGMA integrity_check = ok`, `PRAGMA foreign_key_check` returns empty and `PRAGMA user_version` matches expected. Capture bounded sizes/counts of all known tables. No patient-level content in logs.
4. Derive encryption key from passphrase+fresh salt; authenticate/encrypt the exact snapshot bytes into a private `.part` ciphertext file. Use a background isolate/native implementation as needed to avoid blocking the UI. On large input, streaming AES-GCM requires an independently verified streaming API; v1 otherwise enforces 64 MiB hard cap **before** loading in memory.
5. Reparse and authenticate/decrypt the just-created ciphertext **in private staging**, verify the SQLite snapshot again, then publish only `.medbackup` ciphertext through SAF. Ensure no partially written file is reported as successful (write temporary then commit/finalize; SAF failure means explicit failure). Do not log contents.
6. Clean up private temp ciphertext/plaintext on success, cancellation, exceptions, app restart, and next-launch recovery. Never overwrite/delete the original live SQLite database in export.
7. Show a clear final confirmation with encrypted filename, date, size, all-profile scope and **where it was saved**. The product cannot promise indefinite retention at a cloud/sdcard destination controlled by Android/user.

## 6. Restore pipeline — **two-phase and crash-safe**

**Phase A: read-only validation + preview (no active DB mutation)**

1. User chooses `.medbackup` through SAF `ACTION_OPEN_DOCUMENT`; copy ciphertext into a bounded private staging location. No direct use of an untrusted content URI as a SQLite database.
2. Validate framing, size, KDF limits, support/version and AES-GCM tag using password. On wrong password/tamper, respond `رمز نادرست است یا فایل آسیب دیده` without leaking partial plaintext or changing any records.
3. Write decrypted SQLite only in a private staging path; run integrity/foreign-key/expected-schema/table/ID validation in isolation, with SQLite trusted-schema/defensive safeguards where supported; prevent any execution of attacker-supplied SQL.
4. For supported older schema snapshots, migrate only **the staged copy** to v5 and rerun checks; never migrate the live database during preview. Reject future schema or unsupported legacy version clearly.
5. Present counts: profiles, medications, dose events, stock ledger records, health observations, tasks, visits; show a side-by-side current-vs-backup comparison. Explain **replacement, not merge** and that all current local data will be replaced. Require explicit checkbox + separate destructive-action confirmation. Cancellation leaves everything unchanged.

**Phase B: controlled replace after explicit confirmation**

6. Ensure adequate free space for current DB, staged candidate and an independent rollback copy; freeze UI writes/workers/reminder rescheduling. Finish in-flight transactions, checkpoint SQLite WAL, and **close every open DB connection** before file operations. A Dart `close()` is not sufficient unless confirmed no other open isolate handles are active.
7. Create a rollback copy of the existing database in the same private filesystem and verify it. Install a durable restore journal with states `PREPARED → OLD_SAVED → NEW_INSTALLED → VERIFIED → COMMITTED` to recover predictably from process death at any step.
8. Atomically rename/move staged candidate into the active database path; manage WAL/SHM sidecars only after safe checkpoint/closure. Never delete the rollback copy until the new DB opens and passes `integrity_check`, `foreign_key_check`, version verification and basic repository reads.
9. On verification failure/crash, next app start must detect the journal and roll back automatically to the old DB, restoring normal read/write behavior and explaining the result. File replacement must not happen between distinct Android storage volumes where atomic rename cannot be guaranteed.
10. After commit, re-create application repositories/services and **reconcile** medication/care notification schedules with current permissions, timezone and restored settings; never restore old OS pending notification IDs, duplicate medication events, or send overdue medical reminders immediately without existing scheduling rules.
11. Show `بازیابی کامل شد` only after data verification **and** reminder reconciliation succeeded; distinguish reminder-permission problems without falsely saying patient data was lost. Keep audit record of local restore timestamp/format/version without sensitive fields.

**Hard gate:** if a genuinely crash-safe atomic replacement + rollback cannot be demonstrated on the target Android/Drift implementation, M4-01 may ship encrypted **export + read-only preview** but must disable the restore confirmation action until M4-02 completes. Never ship a best-effort destructive restore.

## 7. Android platform backup privacy gate

Current `android/app/src/main/AndroidManifest.xml` contains no explicit `android:allowBackup` or `android:dataExtractionRules`. Android's `allowBackup` defaults to `true` on typical Android versions; sensitive local SQLite might be transferred by the OS independently of the app's password-protected backup feature. The feature owner must choose and test a privacy policy before public beta.

**Proposed v1 policy:** once manual encrypted export is working and the user has seen a clear retention warning, disable implicit Android cloud backup for app-private health data via `android:allowBackup="false"` and explicit Android 12+ `dataExtractionRules`/pre-12 `fullBackupContent` exclusions. Android 12+ OEM device-to-device transfer can vary despite `allowBackup=false`; tests on target devices are necessary. This is a privacy hardening measure, **not** proof the live DB is encrypted at rest. Do not silently disable recovery paths before informing test users of possible data loss on uninstall.

## 8. Test matrix (automated unless labeled DEVICE)

**Crypto/format:**

1. AES-256-GCM known test vectors and round-trip; output differs for repeated export of identical content.
2. Fresh independent salt+nonce for 1000 back-to-back exports; nonce uniqueness evidence (probabilistic plus mocked RNG boundary tests).
3. Wrong password produces no plaintext; no app database mutation.
4. Flip a bit in ciphertext/header/AAD/tag; every variant rejects before any restore writes.
5. Truncated header, trailing bytes, invalid UTF-8, duplicate JSON keys, unsupported algorithm/version, negative/overflow lengths reject.
6. Bogus Argon2 memory/iteration/parallelism values reject cheaply **before** allocating expensive KDF resources.
7. Password contains Persian and emoji Unicode; export and import round trip without silent trim/normalization.
8. 0-byte, 64-MiB boundary, 64-MiB+1 boundary and high-entropy payload checks.
9. Stored metadata contains no PII; keys and passwords never appear in logs/errors/crash reports.

**Database content/snapshot:**

10. Seed all v5 tables including multiple profiles, plan versions, undo ledger events, health version history, visits/tasks/questions; export and import byte/semantic comparison.
11. Simultaneous writes during consistent snapshot: snapshot has a valid state (no torn transactions or orphan stock ledger entries).
12. WAL mode with uncheckpointed writes; snapshot contains committed data.
13. SQLite `PRAGMA integrity_check` and `foreign_key_check` fail on corrupt candidate, with live DB unchanged.
14. Valid v1..v4 backup migration in staging when supported; unsupported old/future schema refuses without touching live data.
15. No account/internet needed; airplane mode export+restore (DEVICE).
16. No auto-upload or plaintext temp in shared storage; verify private scratch cleanup after success/failure/cancel and process restart (DEVICE).

**Restore data-loss resistance:**

17. Wrong password, malformed frame, wrong app ID, changed schema, broken SQLite, cancel preview all preserve exact original DB hash and reminders.
18. Preview displays every table's relevant count and explicitly compares current/backup datasets.
19. Consent checkbox and destructive confirmation required; back navigation cancels safely.
20. Forced exceptions at every durable journal state restore old or new **fully valid** DB, never half-updated state.
21. Process kill/force stop after `OLD_SAVED` and after `NEW_INSTALLED`, followed by relaunch and automatic safe recovery (DEVICE).
22. Low-storage/disk-full, SAF permission denial, denied output URI, input file removed mid-read: no active-data mutation.
23. Interrupted restore while notification worker running: no duplicate events, no stale app DB handles.
24. Notification permissions denied/granted during restore: retained user data, truthful warning, replan only permitted reminders.
25. 2 profiles with same medication name but distinct IDs remain separate; no cross-profile leakage.
26. A true fresh installation can restore a verified file (DEVICE); original install remains unaffected.
27. Invalid but syntactically well-formed SQLite with malicious schema/triggers never executes attacker-controlled SQL on the active database.

**Privacy/UX/Android:**

28. No public plaintext files, clipboard secrets, backup auto-uploads or logged medical details.
29. Android 11, 12+, 17 emulator backup and D2D policy checks (where available); expected exclusions documented.
30. UI Persian readable; accessible focus/labels, password reveal, error messages, SAF cancellations; no false “success”.
31. Password-loss/uninstall warning visible before creation of first backup.
32. Performance benchmark on supported low-memory emulator and real Android device; no hangs/ANR/OOM during Argon2 and 64-MiB export/restore.

## 9. Implementation packages, separate PRs to control risk

- **M4-01A — review gate:** independent audit of this exact complete contract and PRD mappings; settle file format, crypto/KDF, rollback and Android backup policy. No live user data touched.
- **M4-01B — encrypted export:** pure Dart envelope codec + test vectors, SQL snapshot adapter, SAF save, UI; full unit/widget/device tests. This release may export only.
- **M4-01C — preview and fail-closed restore:** encrypted import, read-only validation and preview, dual-confirmation, staged migration tests; no live replacement until crash gate passes.
- **M4-01D — atomic restore:** journal, rollback, worker freeze, notification replan, kill/crash/low-space tests; only then enable Replace button.
- **M4-02 — separate device-at-rest encryption design:** SQLCipher/Keystore + migration/backup policy tested independently. Accounts/sync/admin/payments remain later packages.

## 10. Review/merge gate and open questions

**Must resolve before implementing crypto:** exact canonical JSON standard or replace with fixed binary header; benchmark Argon2 parameters on Android emulator and minimum supported device; whether selected SAF UI/plugin can guarantee fully written output; exact Drift/SQLite file path and all database handles/isolate lifetimes; reliable atomic rename and rollback behavior; whether current app stores image files outside DB; Android Auto Backup/D2D policy; app version/schema migration acceptance matrix; support-policy limits for total snapshot size.

**No implementation is security-approved merely because `flutter analyze`, unit tests or CI are green.** Require an independent security audit (Gemini/other reviewer), known vectors, integration on real SQLite and Android crash tests; then two-person code review of every destructive restore path. Explicitly keep production or live sensitive health data outside tests.

## Reference material (primary sources)

- Product PRD: `Medication_Health_App_PRD_v1.0_RC_FA.md`, §§7–8, 11.
- Existing code: `apps/mobile/lib/core/storage/app_database.dart`, schema v5 and its migrations; current manifest/notification adapters.
- SQLite documentation: https://www.sqlite.org/lang_vacuum.html (`VACUUM INTO` consistent live snapshot).
- OWASP Password Storage: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html (Argon2id and PBKDF2 guidance).
- Dart cryptography package: https://pub.dev/packages/cryptography (Argon2id and AES-GCM APIs; exact versions pinned after gate).
- Android backup defaults/limitations: https://developer.android.com/guide/topics/manifest/application-element ; https://developer.android.com/about/versions/12/behavior-changes-12 ; https://developer.android.com/privacy-and-security/risks/backup-best-practices .
