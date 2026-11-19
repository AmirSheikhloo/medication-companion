# M4-01D — Admission, fingerprint, locks, journal and fault matrix (D1–D4b-3)

Status: **D1 + D2a + D2b-1 + D2b-2 + D3a + D3b + D3c + D3d (isolated debug) implemented; full M4-01D NOT approved**. This stacked branch is
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

**Remaining D2b requirement:** Connect the *exclusive* native restore owner
to the real Phase B orchestrator, quiesce repository/notification workers, retain an ephemeral preview
consent session (including candidate SHA and logical-data digest), and perform
the under-lock recheck. A shared lease by itself does not authorize writes to
the live DB or implement restore recovery.

## Implemented in D2b-2 — exclusive lock primitive and debug-only self-test

1. Native `acquireRestoreOwner` attempts an **exclusive** kernel file lock and
   requires zero active shared sessions and absent journal/reconcile markers.
   It issues an unguessable owner token and keeps the exclusive lock alive
   until a matching-token release. No public Dart method is provided to
   acquire this restore privilege yet, because crash-safe Phase B is absent.
2. A debug-only, non-destructive `testNativeLockExclusion` method verifies:
   - existing shared DB lease rejects exclusive restore ownership;
   - exclusive ownership rejects another shared DB lease, another exclusive
     owner and regular boot admission;
   - all test leases are released and a subsequent shared admission succeeds.
3. The M0 home screen exposes the clearly labeled **debug-only** test button.
   It must be used only when the medication screen is closed (no active DB).
   It writes no journal, touches no live SQLite data and cancels no alarms.

This is not proof of cross-process/kernel recovery or crash-safe rollback.
The separate-engine/process, kill-point, journal, WAL and notification tests
required by R7 remain unverified. The destructive replacement UI stays off.

## Implemented in D3a — native durable-journal storage probe

1. `NativeRestoreJournal` implements a strictly typed, byte-canonical JSON
   record with checksum across the preceding fields. Parsing refuses extra,
   duplicate, missing, reordered, corrupt or unknown-state fields. It checks
   app-private paths, SHA-256 encodings, UUIDs, size limits and immutable
   operation binding across state transitions.
2. Unique `O_EXCL|O_NOFOLLOW` temporary creation uses explicit write loops,
   `fsync(file)`, same-directory `Os.rename`, and `fsync(parent directory)`.
   Directory creation and terminal unlink also fsync their parent. No journal
   transition permits erasing a nonterminal state.
3. A **debug-only** device probe exercises transitions through `COMMITTED`,
   byte-exact reopening after every update, forbidden backward transitions,
   terminal clearing and deliberate corruption rejection. It operates only
   in a newly generated `backup_journal_probe_<uuid>` directory, removes only
   its own test files and never creates a production restore marker or opens
   the user's SQLite file. The M0 home screen now performs both D2b-2 and D3a
   tests with **one** button.

**Critical limits:** There is deliberately **no production factory** for the
journal store and no Restore Phase B code, because a real recovery owner,
immutable verified rollback master, WAL-sidecar handling, notification
reconciliation and process-kill tests are still missing. A debug probe that
successfully fsyncs a file does not establish crash-safe replacement. The
production store will additionally require a strict per-operation path
allowlist, proof of the actual active DB filesystem device, and native
cross-process crash/restart fault-injection tests.

## Implemented in D3b — isolated Android SQLite rollback fault matrix

1. `NativeRestoreFaultMatrix` creates two valid, synthetic v5 SQLite fixtures
   (`OLD` and `NEW`) under a random, isolated no-backup probe directory; it
   never opens or modifies the application's Drift database. It creates an
   immutable old master and a durable `PREPARED`/`OLD_SAVED` journal record.
2. It simulates a newly installed candidate and stale new-database WAL/SHM
   sidecars, then injects an exception at **four disk checkpoints**: after a
   fully synced rollback copy, after confirmed sidecar unlink + dir fsync,
   after atomic rollback rename + dir fsync, and after durable `ROLLED_BACK`
   journal advancement. A fresh rollback invocation must converge each time,
   checking SHA-256, SQLite integrity, foreign keys, v5 marker, old row value,
   preserved master/candidate, absent incompatible sidecars and removed journal.
3. A fake hot SQLite rollback-journal sidecar is rejected without overwriting
   the active database. A deliberately corrupted rollback master is rejected
   before changing the active candidate. Each simulated fault is isolated and
   only its own synthetic files are removed afterward.
4. The M0 debug page now combines D2b-2/D3a/D3b into **one** non-destructive
   (to the app database) button to reduce repeated user installations/tests.

**This is an exception-injection simulation, not an Android process-kill
test.** It does not demonstrate real cross-process ownership, post-boot
recovery, `old_absent`, actual active Drift-handle shutdown, real checkpoint
classification or reminder reconciliation. Production Phase B remains off.

## D3c — Android old_absent fail-closed sandbox matrix

The existing Android instrumentation test and M0 debug diagnostic now execute
six additional, mutually isolated fresh-install (`oldAbsent=true`) scenarios:
no active file, matching verified candidate, different active contents, stray
WAL, stray SHM, and unexpected rollback-journal sidecar. Each case creates a
fresh random `no_backup/backup_journal_probe_<uuid>` directory, an authenticated
durable PREPARED/OLD_SAVED test journal and a synthetic v5 SQLite candidate.

With no active DB, the test records ROLLED_BACK durably and clears its terminal
journal. With a matching candidate and no sidecars, it verifies SHA/size,
SQLite integrity and v5 contents, advances NEW_INSTALLED → VERIFIED → COMMITTED,
then clears its journal. An unknown active file or unexpected sidecar
**fails closed** without modifying the candidate, active file or OLD_SAVED
journal. Android lstat detects present files without following symlinks.

**Not a production restore implementation:** There is still no production
journal factory, actual process-kill cold-start executor, live-DB replacement,
or alarm reconciliation. All R7 blockers and the Draft PR safety gate remain.

## D3d — real Android process death, isolated debug worker

A separate **non-exported, debug-only** Android ContentProvider runs in
`:m4killprobe`. To avoid killing the Android instrumentation runner, a **host-side GitHub
Actions Python script** uses ADB's `content call` interface to the debug-only
provider. The provider is exported in DEBUG builds only and refuses all callers
except the owning app UID or Android SHELL_UID. The host script records the
provider's PID, asks it to create a random synthetic SQLite probe and durable
journal, then the provider calls `android.os.Process.killProcess(myPid())`
after either `OLD_SAVED` or `NEW_INSTALLED` and before sending any reply.
The host script survives the kill and requests recovery in a newly started
isolated worker process, verifies the PID changed, reopens the persisted
journal, validates SQLite fixtures, and verifies durable `ROLLED_BACK` or
`COMMITTED` output. The instrumentation suite runs first and must pass
before the host-side process-kill script is run.
The test asserts the original immutable master and candidate remain intact.

This is an **actual Android worker-process kill**, not merely a thrown
exception. It is still not a full app-process force-stop, production
cold-start recovery, restored user database, WAL-positive checkpoint,
background Flutter engine, notification reconciliation, or a review of all
R7 kill points. The fixture remains in a random `no_backup` probe folder,
and only the successful test deletes that completed probe. No production
restore is exposed or enabled.

## D4a — read-only preview binding prototype (no Phase B)

A new Dart-only `RestoreReadOnlyPreviewEvidence` prototype captures the v5
logical snapshot SHA-256 (all 17 app tables including optional
`sqlite_sequence`) and an independently streamed SHA-256/byte-count seal of an
**already authenticated and defensively inspected** candidate. An in-memory
monotonic Stopwatch limits the observation lifetime to five minutes by
default. It supports explicit invalidation and a read-only recheck that
fails closed for changed live rows, changed candidate bytes/size, lost
files, changed paths, cancellation, and expiry.

**Safety limitation:** This is a future-facing reusable comparison helper,
not yet wired to the current import-preview UI because that UI intentionally
removes plaintext candidate staging immediately after rendering a read-only
preview. The helper neither acquires the exclusive native Phase B lease nor
authenticates/decrypts candidates, freezes writers, retains a safely bounded
consent session, authorizes restoration, creates a journal, or changes alarms
or databases. Even an `unchanged` result is **not** authorization for
destructive restore. The production Phase B orchestrator and final
under-lock recheck remain unimplemented and blocked by R7.

Automated unit tests cover unchanged files, same-count live-data mutations,
same-size candidate mutation, truncated/deleted candidates, missing live DB,
invalidated/expired evidence, and path rebinding. Real Android process-kill
tests D3d remain separate from this Dart-only prototype.

## D4b-1 — ephemeral read-only import retention & checked native cleanup

The validated Phase A import-preview screen retains its authenticated,
defensively inspected `import.sqlite` quarantine for **at most five minutes**
in an app-private `no_backup/backup_staging/<UUID>` directory. The session
uses the D4a logical-data/byte-seal recheck, exposes separate **read-only
recheck** and **cancel & discard** buttons, and invalidates the evidence when
the app leaves foreground, the screen is disposed, a new import begins, or
the timer expires. Even an unchanged recheck does not grant user consent or
enable a destructive restore action. No private medical rows/hashes or paths
are shown in the interface.

A `ReadOnlyImportRetention` helper owns the cleanup callback and refuses to
report cleanup success unless Android explicitly acknowledges deletion. A
failed cleanup is retryable. Android's `clearImport` is now strict: it allows
only a UUID-scoped import quarantine, rejects unknown or symlinked sidecars,
checks each unlink, fsyncs the directory, and only then removes the folder
and fsyncs the staging parent. The normal cold-start sweep remains the
crash fallback; do not treat its best-effort cleanup as Phase B completion.

Dart unit tests cover preserved read-only files, changed live data with equal
row counts, cancellation, cleanup failure/retry, and timeout. Android tests
cover idempotent cleanup and rejecting unexpected files in a synthetic
quarantine. **No production exclusive restore ownership, consent token,
candidate source-to-commit authentication, WAL replacement, or alarm
reconciliation has been implemented**; R7 still blocks Phase B.

## D4b-2 — read-only exclusive-owner fixture gate and alarm-plan invariants

D4b-2 adds a **synthetic, instrumented Android proof** for the future
exclusive Phase B boundary. The core production lock remains private and
there is **no MethodChannel**, UI route, consent token or destructive
replacement API that can acquire the restore owner.

- `NativeBackupStartupGate.withExclusiveFixtureOwnerForTest` holds the same
  kernel-backed exclusive lock for the entire test callback and always releases
  it after completion or an exception. This API is deliberately fixture-only.
- Android instrumentation creates small, unique SQLite fixtures only under
  `no_backup/backup_journal_probe_<UUID>`; no real Drift database, rollback
  master, restore journal or Android alarm is accessed.
- Two in-process lifetime-held shared leases prevent an exclusive owner until
  **both** close. During the exclusive read-only callback, new ordinary
  admission fails both in-process **and from an actual second Android process**
  (`:m4killprobe`); after release both can acquire compatible leases again.
- Under exclusive fixture ownership, a deterministic synthetic SQLite row
  fingerprint plus a bounded candidate size/SHA-256 reject same-count live row
  mutations and same-size candidate corruption. A repeated unchanged check
  succeeds; an exception releases ownership.
- Medication and care reminder tests verify that repeated reconciliation of
  unchanged schedules preserves stable IDs and inserts no dose/stock/care
  history. Permission revocation prevents new scheduling attempts and retains
  truthful enabled-state reporting.

These checks cover **admission and pure preflight evidence only**. They do
not prove the production Phase B lifecycle handoff (actual Drift closure,
profile/callback freeze, v5 17-table recheck under exclusive ownership,
persistent reconcile marker, alarm cancellation/rebuild, WAL checkpoint,
rollback journal, production crash recovery or full R7 matrix). In
particular, synthetic fixture hashing is **not** a substitute for the
canonical 17-table logical fingerprint in the R7 contract. The destructive
Replace action remains **absent** and PR #19 stays **DRAFT**.

## D4b-3 — real exclusive-owner process death and fail-closed marker tests

This stage extends the isolated fixture evidence to cover critical Android
lifecycle failures that were not exercised by D4b-2:

1. The debug-only second Android process takes the **actual native exclusive
   lifecycle file lock**, writes and fsyncs a PID witness under a unique
   `no_backup/backup_journal_probe_<UUID>` fixture, and then dies via
   `Process.killProcess(myPid())` **before releasing the lock**. The
   independent ADB host script verifies a new PID, the previous owner's
   durable witness, and successful shared-session admission after OS cleanup.
   The actual Drift database, alarm set and production journal are untouched.
2. Android instrumentation now tests separate-process boot admission denial
   while the exclusive owner is held, ordinary admission recovery after
   release, and every synthetic durable `restore_journal` /
   `reconcile_pending` exact or torn-prefix marker. All marker tests use an
   isolated ContextWrapper pointing at a random probe folder; a rejected
   marker cannot authorize a shared lease or an exclusive owner.
3. The GitHub CI workflow tests the reusable PowerShell preview installer
   selection with a synthetic mixed list (old/current/new CI versions, base
   app, unrelated packages and hostile suffix). The built artifact includes
   the installer alongside the APK. **Only strictly older numbered CI preview
   packages** are uninstalled, and only after validating and launching the new
   APK; the base application and newer previews are preserved.

These are additional safety proofs, **not completion of the production Phase B
gate**. They do not close/reopen real Drift sessions, recheck the live 17-table
fingerprint under an exclusive owner, create the production durable journal,
handle real WAL checkpoint ownership, or reconcile actual alarms. Destructive
replacement stays disabled and PR #19 remains DRAFT. Formal R7 release-gate
count is unchanged.

## Required work before enabling replacement (D2–D4)

- Device validation of the **lifetime-held** native lease (including a
  separate headless Flutter engine and Android process), plus a complete
  Phase B orchestrator controlling the D2b-2 exclusive owner. The original D1
  momentary boot probe remains distinct and cannot authorize replacement.
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
