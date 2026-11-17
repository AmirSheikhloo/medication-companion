# M4-01B — Encrypted Export Implementation Status

**State:** FOUNDATION ONLY — NOT A SHIPPABLE BACKUP FEATURE.

## Scope committed in this pull request

- Strict 105-byte MCBK v1 AAD builder and untrusted prefix parser.
- Exact 90-byte fixed header, 121-byte ciphertext framing overhead.
- Strict pre-KDF bounds: file size, 64 MiB payload ceiling, future schema
  rejection, approved Argon2id tuple, flags, timestamp, length overflow.
- Tests for malformed/oversized input and deterministic field offsets.

**This code is not a cryptographic implementation** and MUST NOT be
advertised as an encrypted backup. No UI to create/restore files is exposed.

## Required before enabling export (R7 §5 / M4-01B)

1. Pin reviewed, native Android Argon2id with approved (65536, 3, 1)
   parameters, 32-byte derived key, memory-failure and ABI tests.
2. Pin proven incremental AES-256-GCM whose entire Java/Dart/native RSS
   remains bounded for a 64 MiB payload. Check tag at finalization; keep
   plaintext private until authentication. Verify x86_64 AND arm64.
3. Create transactionally consistent SQLite snapshot with bound
   VACUUM INTO (or separately qualified backup API). Test committed WAL
   writes and all 17 tables. Snapshot is stored privately.
4. Add full round-trip decrypt/verify and fresh nonce+salt generation,
   including independent test vectors.
5. Add Android SAF ACTION_CREATE_DOCUMENT integration: stream encrypted
   bytes only, check close/readback errors, cleanup orphan/partial output
   where supported, and provide accurate export status.
6. Add explicit password handling, account/uninstall warnings, cancellation
   semantics and RTL UI.
7. Gate every aspect behind Flutter analyze/tests, Android APK compilation,
   device memory profiling, and independent review.

## Non-negotiable safety gates

- Do not use ordinary Java Cipher.update as proof of streaming GCM.
- Never write unencrypted backup files to shared storage.
- No destructive restore implementation in M4-01B.
- Do not merge this PR as a completed M4-01B delivery.
- App runtime behavior and user SQLite remain unchanged by this foundation.

Authoritative contract: docs/M4_01_SECURE_LOCAL_BACKUP_CONTRACT_R7.md
