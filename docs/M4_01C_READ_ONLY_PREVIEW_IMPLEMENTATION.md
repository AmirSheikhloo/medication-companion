# M4-01C — authenticated backup import and safe preview (candidate)

Status: **DRAFT — no restore performed.** This branch targets M4-01B and is
not approved for use with irreplaceable medical data until CI and physical or
emulator security tests pass. R7 remains authoritative.

## Implemented

- Android SAF `ACTION_OPEN_DOCUMENT` input; hard cap 64 MiB + 121 bytes;
  explicit zero/tiny/oversized advertised sizes are rejected; unknown lengths
  are stream-capped and actual bytes counted; files are staged under
  `noBackupFilesDir/backup_staging/<UUID>` only.
- Fixed-position 105-byte `MCBK v1` prefix checked before password KDF;
  memory bounded Argon2id and incremental AES-256-GCM authenticated decryption
  reuse the M4-01B engine. No SQLite is opened until tag verification succeeds.
- A quarantined plaintext SQLite snapshot is opened **read-only**, with
  fail-closed SQLite db_config flags and a low-level FFI
  `sqlite3_set_authorizer`, using **the same native asset** as package:sqlite3.
  Only whitelisted SELECT/READ/PRAGMA/functions are authorized; all writes,
  ATTACH/DETACH, schema DDL, savepoints and unknown actions are denied.
- Candidate's entire `sqlite_master` schema matches the installed v5 schema
  (17 expected tables, no additional view/trigger/virtual object/index), plus
  `PRAGMA user_version`, page bounds, `integrity_check(10)`,
  `foreign_key_check`, and counted rows.
- UI displays selected eight high-value categories' live vs backup counts,
  without a restore button. Native staging cleanup runs in `finally`, with
  cold-launch cleanup for interrupted processes.

## Deliberate boundaries / remaining gates

1. **M4-01D not implemented.** There is no restore, migration, WAL swap,
   recovery journal, or notification reconcile in this branch.
2. Old `user_version` 1–4, or v5 schemas whose SQL differs from the running
   app's v5 schema, are rejected. Support needs fixture-verified offline
   migrations in M4-01D; do not loosen schema checks as a workaround.
3. Need a real Android emulator/phone test: SAF file from Downloads and cloud
   providers, correct and incorrect passphrases, corrupted tag, truncated and
   oversized files, an extra SQLite view, interrupted import and cold restart.
   Confirm the live data remains unchanged in every failure.
4. M4-01B KDF uses BouncyCastle Java rather than the fully native/FFI profile
   required by R7; a release-grade native performance/memory gate remains.
5. Trust boundary: this v5 schema comparison uses the *installed* live Drift
   schema as a local baseline, not a published per-version fixture hash.
   A maliciously modified local database is outside this beta trust model.
6. Safety regression test depends on the *same* `sqlite3` native asset
   exposing `sqlite3_set_authorizer`. The initial Android preview failed
   closed at this gate. Inspection of the shipped x86_64 `libsqlite3.so` with
   `readelf -Ws` confirmed the symbol was missing. The upstream prebuilt
   `package:sqlite3` library deliberately compiles with
   `SQLITE_OMIT_AUTHORIZATION`; this is not repairable via FFI declarations.
   Android now builds a pinned SQLite amalgamation from the `rusqlite`
   submodule with `default_options: false` and `SQLITE_THREADSAFE=1`. Linux CI
   retains the system library. The Android artifact gate checks the dynamic
   export of `sqlite3_set_authorizer` for every packaged ABI. Device testing
   must still prove callback invocation, schema checks and fail-closed
   behavior. Never fall back to unauthenticated inspection.
7. GitHub Actions can sign different runs with different temporary debug
   certificates. The CI-only Gradle `debug` configuration isolates **each CI
   run** with `applicationIdSuffix=.m4r<GITHUB_RUN_NUMBER>` to preserve both
   the local app and all earlier test data without uninstalling anything.
   The new APK has a fresh local database; testers must create synthetic
   sample data for the source-versus-preview count comparison. The previous
   `.m401preview` test build is unaffected and may remain installed.

## Android native authorization prerequisite

The amalgamation is pinned at `rusqlite` tag `v0.41.1`, commit
`18ee76dbb976d5ef7e37ad5a8fffae678ca21a78`, under
`apps/mobile/third_party/rusqlite` as a Git submodule. For a fresh local
checkout, from the repository root run:

```powershell
git submodule update --init --depth 1
```

The Android `source: source` hook compiles against
`third_party/rusqlite/libsqlite3-sys/sqlite3/sqlite3.c` and must export
`sqlite3_set_authorizer`. CI checks the packaged `.so` symbol table; a
green Linux unit test alone is not sufficient evidence. Initial user tests
with API 37 verified that the encrypted export/snapshot succeeded before
the authorizer omission was detected in import preview. The encrypted
file and live app data were not replaced.
