# M4-01D — Recovery admission, logical fingerprint and DB leases (D1 + D2a + D2b-1)

Status: **D1 + D2a + D2b-1 implemented, full M4-01D NOT approved**. This stacked branch is
based on M4-01C. The R7 contract remains authoritative. No destructive restore
action or replacement of the active SQLite database is exposed.

## Implemented in D1

1. `NativeBackupStartupGate` uses a native process monitor plus an Android
   kernel-backed file lock in `getNoBackupFilesDir()`. If CE storage is locked,
   the lock is unavailable, the journal directory is unreadable/ambiguous, or
   `restore_journal.json` / `reconcile_pending.flag` (including partial marker
   filenames) is present, it fails closed. A marker is rechecked **under** the
   lock. This is a non-destructive **admission probe**, not yet a lifetime-held
   SQLite session lease or an exclusive Restore Phase B owner.
2. `main()` now awaits `RestoreStartupGate.runBeforeAppStart()` after Flutter
   binding initialization and before `runApp`, `AppDatabase`, notifications,
   repositories and coordinators. Unknown results and platform-channel failures
   display a recovery-only screen without touching the live database. Staging
   cleanup moved from native `configureFlutterEngine()` to after a successful
   recovery probe; it does not delete pending-journal-owned files.
3. `SafeScheduledNotificationBootReceiver` is the only manifest-registered
   boot rescheduler. The original plugin receiver is removed in the merged
   manifest; after native admission passes, it calls the *public*
   `ScheduledNotificationBootReceiver.onReceive(context, intent)` from pinned
   `flutter_local_notifications: 23.0.2`. The same four intent actions are
   retained. On error or any recovery ambiguity, it suppresses replay.
4. Flutter unit tests check explicit allow, explicit deny, absent method
   channel and platform error. Android CI checks the actual APK manifest to
   ensure the plugin receiver cannot be independently registered and validates
   the SQLite authorizer symbols in all three ABI libraries.

## Implemented in D2a — preview-time logical fingerprint

1. An isolated read-only native SQLite session reads the installed v5 database
   inside **one SQLite read transaction**, returning exactly 17 table counts
   and a single SHA-256 of deterministic logical contents.
2. Fingerprinting domain-separates the format, includes the schema signature,
   all ordered table/column names and all rows in stable binary-PK order, and
   type/length-encodes NULL, 64-bit integers, IEEE doubles, UTF-8 and BLOBs.
   It also includes `sqlite_sequence` **only if it exists** (including its
   high-water marks), never unconditionally queries an absent internal table.
3. The read-only import preview now uses counts produced by this same snapshot
   instead of eight separate, potentially inconsistent live SELECTs. All
   streaming row access runs off the UI isolate, without collecting plaintext
   patient records into Dart lists and without logging record-level hashes.
4. Tests check deterministic ordering, row-content changes despite identical
   counts, the absence/presence of `sqlite_sequence`, sequence-only mutation,
   and fail-closed database-version mismatch.

**Not implemented in D2a:** The UI intentionally discards this digest when
preview ends because the candidate staging file is still cleared and the
destructive confirmation action is still disabled. D2b must retain the full
fingerprint, staged candidate SHA and bounded consent session in memory only;
then the exclusive Phase B owner must re-capture and compare both before any
side effect. D2a does not itself make destructive restore safe.

## Implemented in D2b-1 — lifetime native DB session admission

1. The app's only production `AppDatabase` creation path is now the async
   `AppDatabase.openGuarded()`, which obtains `DatabaseLifecycleLease` before
   constructing the lazy Drift executor. Direct runtime construction is
   private; `AppDatabase.forTesting` remains exclusively for injected
   test executors. Channel absence/denial fails closed.
2. A native, shared kernel `FileLock` on `database_lifecycle.lock` stays open
   for the entire lifetime of registered Drift sessions. An in-process
   synchronized token registry supports concurrent Flutter sessions without
   overlapping JVM file locks; each token must be explicitly released after
   `await AppDatabase.close()`. A different process can only take an exclusive
   recovery lock when all shared sessions have stopped.
3. The Android boot probe recognizes already-active, valid shared sessions,
   but still checks durable restore/reconciliation markers before allowing
   replay. Native failures and unacknowledged release cannot be treated as
   permission to open a database.
4. Mocked Flutter tests cover admission, missing channel, denial, errors,
   explicit token release and idempotent acknowledged close. Native concurrent
   ref-count and OS lock tests are still required on Android devices.

**Remaining D2b requirement:** Add the *exclusive* native restore owner,
quiesce active repository/notification workers, retain an ephemeral preview
consent session (including candidate SHA and logical-data digest), and perform
the under-lock recheck. A shared lease by itself does not authorize writes to
the live DB or implement restore recovery.

## Required work before enabling replacement (D2–D4)

- Device validation of the **lifetime-held** native lease (including a
  separate headless Flutter engine and Android process), with a native
  exclusive restore owner. The original D1 momentary boot probe remains
  distinct from the D2b-1 lease and cannot authorize replacement.
- Two separate consent actions, candidate SHA and strict **recheck** of the
  D2a snapshot after quiescing writers. Legacy schema migrations remain blocked
  until complete fixtures and exact authorizer/FK transaction tests exist.
- Real native durable journal/fsync of files and parent directories, same
  device check, immutable rollback master, WAL-safe sidecar handling, retryable
  PREPARED/OLD_SAVED/NEW_INSTALLED/VERIFIED/COMMITTED/ROLLED_BACK state machine
  and a recovery-only diagnostic pathway on corrupted journal.
- Idempotent managed-alarm rebuild and permission-aware marker removal,
  supported process-kill/reboot tests, and the remaining R7 matrix cases.
- Native Argon2id implementation/performance instead of the current Java
  BouncyCastle KDF; this remains a release-blocking R7 deviation.

**Explicit stop rule:** If any lifetime lease, native journal, recovery or
notification test is unverified, Phase B is disabled and read-only preview
remains the furthest user operation. Never infer a successful recovery from
a green Linux unit test or a successful APK build alone.
