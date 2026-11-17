# M4-01B — Encrypted local export implementation / device test gate

State: **implementation candidate — NOT release-approved until Android/device gates**.
Base: `docs/M4_01_SECURE_LOCAL_BACKUP_CONTRACT_R7.md` (approved M4-01A).
Scope: export only. **No import, restore, live database replacement, notification cancellation, or schema migration.**

## Code map

- `apps/mobile/lib/features/backup/presentation/secure_backup_screen.dart`: Persian passphrase and confirmation; SAF picker, status and non-recoverability warning.
- `apps/mobile/lib/features/backup/domain/backup_password_policy.dart`: Unicode code-point policy, no trimming/normalization.
- `apps/mobile/lib/features/backup/domain/mcbk_v1.dart`: independently reviewed Dart v1 framing/strict untrusted header parser (consolidated from PR #16), with adversarial header tests.
- `apps/mobile/android/app/src/main/kotlin/ir/example/medication_companion/MainActivity.kt`: Android SAF picker and bounded single-worker channel orchestration.
- `apps/mobile/android/app/src/main/kotlin/ir/example/medication_companion/SecureBackupEngine.kt`: SQLite `VACUUM INTO ?` on a read-only isolated connection, v5 integrity/FK/table-count verification, fixed 105-byte framing, native Android-side Argon2id, Bouncy Castle lightweight incremental GCM, local decrypt-and-verify, SAF file-streaming and readback.
- `apps/mobile/android/app/src/main/AndroidManifest.xml`: no Android backup/device transfer of medical storage.

## Encryption format

`MCBK v1` uses 105 raw AAD bytes + N ciphertext bytes + 16 GCM tag bytes. All fixed field offsets and size caps are those from R7 §4. Argon2id profile is `m=65536 KiB / t=3 / p=1 / version=0x13`; AES-256-GCM uses 12-byte random nonce and one 16-byte tag. Source snapshot is **v5 SQLite** (17 real tables) and includes committed WAL data. No plaintext or secret material goes to SAF, logs, cloud APIs or shared storage. Private staging is inside Android `noBackupFilesDir` and removed in `finally`.

### Native provider exception / open gate

This candidate uses the pinned `org.bouncycastle:bcprov-jdk18on:1.86` Android Java **lightweight** `GCMBlockCipher`/`Argon2BytesGenerator` rather than an FFI-wrapped C Argon2 reference implementation. Bouncy Castle GCM `processBytes` is block-streaming and differs materially from Android Conscrypt `Cipher.update`, which can accumulate the complete input. **R7 §3 prefers audited native/FFI Argon2**; Android JVM-side KDF is a documented deviation requiring independent approval or replacement with pinned native C before release. Never label this deviation as having passed R7 automatically. Pin/verify the *actual* BC classes loaded on Android (platform classloader interference), the 64 MiB benchmark, and cross-runtime vectors before signing off.

## Required automated / device verification before release

1. GitHub Actions: `flutter pub get`, `build_runner`, `flutter analyze`, `flutter test`, `flutter build apk --debug`. No source-code test alone replaces emulator tests.
2. On Android emulator API 37 x86_64, launch app, create profile/medication/dose/stock/health/visit/task, enter **the same >=12-code-point Persian/emoji password twice**, choose an actual SAF destination. Expect success with verified readback if the provider permits reopening. Confirm `.medbackup` begins with `MCBK` and file length is `121 + ciphertext_length`; no `.sqlite`, password, or plaintext is exported.
   First press **تست موتور رمزنگاری — نسخه آزمایشی**: it must match a fixed cross-runtime Argon2id13/AES-GCM known-answer vector before any export is attempted.
3. Repeat immediately with unchanged data: bytes differ (fresh ID/salt/nonce). Restart the app, ensure all existing records remain. Test canceling file picker; no database mutation and no false success. Test mismatched/short passwords; picker never launches.
4. Test no-space, disconnected/unreadable provider, refused write, failed readback and process interruption. Do not claim permanently durable remote storage after readback success. Where a provider permits deletion, partial output should be removed.
5. **Blocking hardware gates:** Build and run on arm64-v8a and x86_64; derive Argon2id known-answer vector with independent reference; decrypt on a second device/runtime using fixed R7 header offsets; encrypt/decrypt a truly 64 MiB incompressible SQLite fixture with real Java heap/native/RSS profile (including both KDF runs) on minimum 2–3 GB RAM device; check no ANR/OOM. Confirm provider `GCMBlockCipher` is actually incremental (no whole-input buffer); inspect end-to-end output and memory. Verify SQLite snapshot when WAL contains unapplied committed pages. Negative cases (tag, ciphertext, header tamper and truncation) must never make plaintext public.
6. User must test SAF on emulator: device's `Downloads` provider plus a second available provider if practical. **No merge or release until all blocking items are green.**

### Independent cryptographic known-answer vector (test-only, never production)

Derived using libsodium Argon2id13 `crypto_pwhash` (`m=64 MiB`, `t=3`, `p=1`) and `cryptography` OpenSSL-backed AES-256-GCM, independently from the Android implementation:

- Password UTF-8: `M4-01 vector فارسی🌷 2026!`
- Salt: bytes `00..0f`; nonce: `10..1b`; backup ID: `20..2f`; timestamp: `1794910000000`; schema: `5`; ciphertext size: `4096`.
- Test plaintext (crypto format fixture only, **not** a valid SQLite DB): ASCII `SQLite format 3\0` followed by 4080 zero bytes.
- 32-byte Argon2id key: `ecc6fe38b3878f93ac4e08419b09f4b17658bf02abd7f0da7be61601eb00827f`
- SHA-256 of 105-byte prefix: `f5a1820e868405daa346d14bd0fa4675c4e9778672856811f40d5c8a5797d423`
- First 16 ciphertext bytes: `330c29c7c4e9842357dadec814a33a33`
- Final 16-byte GCM tag: `8e450e33fa3a8e47a103ec3a1494272f`
- SHA-256 of the full 4217-byte envelope: `6e22ddbca135a55a2ec5e4febfd730c8c94cd17ee7f30138abc7b4c34851106f`

The debug UI tests the derived key, complete envelope hash, and authenticated decrypt against this fixture without touching user records, and fails closed when any check differs.

## Exact Windows steps (once CI is green)

Open PowerShell (paste **commands only**, not the `PS C:\...>` prompt):

```powershell
cd "C:\Users\amir\Projects\medication-companion"
git status --short
git pull --ff-only origin main
cd apps/mobile
flutter pub get
flutter devices
flutter run -d emulator-5554
```

For testing the **draft PR branch** before merge, replace the `git pull` line above with `git fetch origin feature/m4-01b-encrypted-export` and `git switch --track origin/feature/m4-01b-encrypted-export` (if already created locally, use `git switch feature/m4-01b-encrypted-export` instead). Keep uncommitted `pubspec.lock` changes; do not reset or delete them.

Alternatively, download the `medication-companion-debug-apk` artifact from the newest green run under PR #17 → **Checks** → **Details** → **Artifacts**, unzip it and install `app-debug.apk` on the emulator via Android Studio or `adb install -r`. This avoids local Dart/Gradle download blockers.

In the app open **ورود به بخش داروهای من ← بیشتر ← پشتیبان و بازیابی ← ساخت پشتیبان رمزگذاری‌شده**. Enter the same long Persian passphrase twice, tap **انتخاب محل و ساخت پشتیبان**, choose Downloads and confirm. Wait for explicit readback success or the explicit unverified-provider warning. Retain the encrypted file for M4-01C read-only preview tests. If `flutter pub get` fails with `pub.dev 403`, fix configured mirror/network first; `flutter run --no-pub` only when dependencies already match.
