# M4-01D — Recovery admission and Android boot guard (implementation slice D1)

Status: **D1 implemented, full M4-01D NOT approved**. This stacked branch is
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

## Required work before enabling replacement (D2–D4)

- A **lifetime-held** database admission lease for every Drift/native handle,
  verified background/other-engine behavior, and a native exclusive restore
  owner. The D1 momentary probe **must not** be treated as that lease.
- A consistent, all-table logical fingerprint including optional
  `sqlite_sequence`, two separate consent actions, candidate SHA and strict
  recheck after quiescing writers. Legacy schema migrations remain blocked
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
