# Medication Companion — همراه دارو

An Android-first, offline-first medication companion built with Flutter.

> **Current status:** M0 engineering spike. The Android notification, exact-alarm, full-screen intent, and PDF export paths are experiments, not a production medication-reminder system. Do not use this prototype for clinical decisions.

## Repository layout

| Path | Responsibility | Deployment |
| --- | --- | --- |
| `apps/mobile/` | Flutter Android application | Android APK / AAB |
| `apps/admin/` (future) | Web administration UI | Independent web deployment |
| `services/api/` (future) | Server API and business services | Independent server deployment |
| `packages/contracts/` (future) | Versioned API schemas and generated clients | Not deployed as a service |
| `docs/` | Architecture, decisions, acceptance criteria | Documentation |

Only `apps/mobile/` exists today. Future directories are created when their first real feature needs them. There is no runtime dependency between deployable apps.

## Run the mobile prototype

From the repository root:

```powershell
cd apps/mobile
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d <ANDROID_DEVICE_ID>
```

Use the actual device ID reported by `flutter devices`. This repository does not require Visual Studio for Android development.

## Engineering workflow

1. Create a feature branch from `main`.
2. Keep changes scoped to one feature or infrastructure concern.
3. Run analyzer and tests locally; GitHub Actions also checks mobile changes.
4. Open a pull request and review its checks before merging.
5. Pull the merged `main` branch onto the development PC.

See [Architecture](docs/ARCHITECTURE.md) for ownership and deployment boundaries.

## Safety

- Never commit credentials, signing keys, real patient records, or personal health data.
- Keep test fixtures synthetic.
- The current M0 PDF has a known Persian glyph-rendering issue; full report rendering will be addressed in the reporting module.
- No backend, account system, cloud synchronization, medical advice, or production scheduling guarantee is implemented yet.
