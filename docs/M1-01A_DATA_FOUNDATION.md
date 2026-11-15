# M1-01A — Offline medication data foundation (review candidate)

## Purpose
Add a testable **offline data layer** in the Flutter app without replacing the
working M0 notification/PDF diagnostic screen or changing its 5- and 10-second
test schedules. This PR is infrastructure only; no M1 UI has been connected yet.

## Module boundaries
- `lib/core/storage/app_database.dart`: Drift SQLite schema and migration gate.
- `lib/features/profiles/data/profile_repository.dart`: guest/managed profile
  creation, selection, and scoped profile reads.
- `lib/features/medications/domain/occurrence.dart`: deterministic daily
  occurrence identity based on immutable plan-version ID plus local calendar day.
- `lib/features/medications/data/medication_repository.dart`: medication
  creation, scheduled-dose projection, and append-only dose event history.
- `lib/m0/` and current `lib/main.dart`: unchanged working M0 diagnostics.

No admin panel or backend service code belongs inside the Flutter application.
Future deployables will live under independent `apps/admin/` and `services/api/`.

## Behavior and limits
- Each medication belongs to one explicitly selected profile.
- Each medication currently supports **one daily time** and one initial plan
  version. Future schedule edits need versioning and migration tests.
- `recordDose` updates the effective status and appends a dose event in the
  same transaction. Repeated "taken" cannot silently create extra events; an
  undo appends a new event rather than deleting history.
- This foundation does **not** schedule actual medication reminders, validate
  prescriptions, sync online, or implement stock/FEFO.
- The local database is **not encrypted at rest yet**. Use fictional demo
  data only; **do not enter real medication or personal health information**.
- The PDF Persian-glyph issue is deferred to a separate reporting task.

## Schema and generated code
Schema version is 1. Upgrades without an explicitly implemented migration are
rejected; never clear health data to make a migration pass.

The `app_database.g.dart` file is generated, not hand-edited or committed.
After pulling this change, from `apps/mobile` run:

```powershell
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

CI runs the generator before `flutter analyze` and `flutter test`.
The existing M0 application should still launch as before.

## Next gate (M1-01B)
Connect the profile/medication data layer to modular mobile screens while
retaining M0 diagnostics as a separate reachable screen. Add widget and manual
Samsung A52s tests before allowing real-life usage.
