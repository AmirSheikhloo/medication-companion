# M2-02 — Offline multi-package inventory, exact ledger, and dose reconciliation

## Scope

- SQLite Drift schema v2, **additive 1 -> 2 migration**. Previous Profiles, AppSettings, Medications, MedicationPlanVersions, DoseEvents, and DoseCurrentStates are untouched. Database filename stays `medication_companion_m1`.
- Per-profile/per-medication packages with independent label, declared unit, positive/zero initial quantity, optional Gregorian day or month precision expiry, and user-selected package.
- Append-only `stock_movements` journal of initial, adjustment, taken, and undo with signed **integer thousandths**; no floating point balance, mutable balance counters, destructive row updates, or silent cross-unit aggregation.
- User-configurable per-medication quantity alert stored with the **selected package unit** and checked only against a selected package of that same unit (never silently reinterpreted after changing units). No calculated "days left" since doseText is free text and schedules may be variable.
- On `taken`, explicitly ask user for actual amount, or offer `taken without debit`. No extraction of quantity from dose text; no stock is deducted by default.
- Dose event and stock debit/undo always occur in one database transaction. Duplicate `taken`/undo requests do nothing; insufficient stock and expired/unselected packages reject debit without creating a dose event. Undo inserts one exact compensating movement, never removes the original.
- Stock changes do not modify reminders; existing opt-in M2 reminder behavior and M0 diagnostics remain intact.
- M2-02B follow-up: read-only per-package movement history in the inventory sheet, with timestamp, movement type, signed amount, and user-entered reason; inline and Snackbar confirmation for successfully saved stock operations and explicit threshold status.

## Constraints, non-goals

- Demonstration only: the local DB is **not encrypted** and lacks backups, cloud sync, account authorization, multi-device stock reconciliation, and production reliability validation. Use fictional data only.
- Expiry selection in this milestone uses a **Gregorian** date picker; it records precision (`day` or `month`) and refuses to debit a package that is expired by that declared date. Original packaging, calendar system, and actual medicine suitability require separate verification. Jalali input and manufacturer-specific expiry semantics remain future work.
- No automatic batch choice or FEFO/FIFO; the user must select a package. Different units are not summed or converted.
- A recorded dose is a statement by the user, not medical advice or validation.

## Validation gates

1. CI `dart run build_runner build`, `flutter analyze`, and `flutter test`.
2. New tests cover exact quantity parsing, expiry boundaries, independent package balances/units, profile ownership, ledger adjustments, low-stock rules, one-time debit/compensating undo, insufficient stock rollbacks, explicit no-debit records, and v1->v2 preservation of all previous dose tables.
3. On emulator, test package creation (two distinct units), manual selection, alerts, quantity deduction, undo, insufficient stock, expiry and per-package audit history; check that saving a threshold produces visible confirmation; exit and reenter to verify persistence.
4. Before any real-world use: test migration against copied on-device DB, storage encryption/backup policy, Android 14 physical device reminders, reboot/timezone/OEM behavior, and real-world clinical UX.

## Developer update procedure (Windows PowerShell)

```powershell
cd "C:\Users\amir\Projects\medication-companion"
git status --short
git pull --ff-only origin main
cd apps\mobile
$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run -d emulator-5554
```

Do **not** uninstall the app or clear its data: those actions erase local demonstration records. A `flutter clean` is not necessary for these tests.
