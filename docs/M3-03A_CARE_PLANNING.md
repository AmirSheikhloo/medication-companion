# M3-03A — Offline care planning / برنامهٔ پیگیری و ویزیت

## Scope

- Profile-isolated, offline **visits** (title, time, optional doctor, center, purpose, status; edit).
- **Tasks** (title, optional due date and visit link, open/done/deferred, edit, archive). Append-only task activity events are retained locally.
- Per-visit editable **pre-visit and post-visit checklists**, initially seeded with practical nonmedical prompts; add, remove, reorder, enable/disable, check/uncheck.
- **Questions** with an optional visit link, answered/unanswered and archive.
- Entry point on Today and More; clear save acknowledgment; no automatic changes to dose or medication schedule.
- Drift additive schema **v4**. Existing v1, v2, v3 databases upgrade without deleting medication, inventory, or health records.

## Explicit deferrals

- M3-03B: opt-in Android notification scheduling for visit/task reminders, repeat rules for tasks, 3-month course follow-ups, calendar integration, and notifications showing checklists the day before a visit. No UI toggle claims notifications are scheduled in M3-03A.
- This release is a local demonstration. It has **no encrypted storage/backup** or multi-device sync. Use fictitious patient data only.
- Do not infer medical treatment from a task or checklist; no medication is stopped or changed automatically.

## Tests and verification

CI: Flutter analyze, unit/widget tests, and Android debug APK build. Unit tests cover:

1. New visit persists with 5 before / 3 after checklist defaults.
2. Checklist check/disable/move/add/remove, including disabled-item guard.
3. Task edit/defer/done/archive with immutable event trail.
4. Questions with optional visit link and answered/archive.
5. Cross-profile reads, writes, references, and checklist access rejected.
6. Direct v3 → v4 migration; original v1 → v4 migration regression.
7. UI creates a task and checks a visit checklist.

## Manual emulator acceptance (stop on the first mismatch)

1. Update main, run `flutter pub get`, generate Drift code and run tests, launch emulator.
2. Existing medications, stocks, measurements and charts still appear; no data resets.
3. Today → «کارهای پیگیری، ویزیت‌ها و سؤال‌های پزشک» opens planner for current profile.
4. Create a task without date. Check it appears as open; tap it to mark done.
5. Change it to deferred using menu, edit title and due date; reopen and archive.
6. Create a visit for a chosen date/time; optionally enter doctor/center/purpose.
7. Open visit and see 5 pre-visit and 3 post-visit checklist items.
8. Check an item, disable another, move one up and add/remove one; revisit and verify persistence.
9. Add a question inside the visit; mark answered; find it in the global Questions list.
10. Add a standalone question, answer and archive; confirm it disappears from active view.
11. Switch active profile in More, open planner: prior profile's care data must be invisible.
12. Switch back and restart app: original care data persists. No medication schedule is altered.

Date/time picker is explicitly Gregorian in M3-03A; displayed appointments are local device time. Device notifications for tasks/visits are not yet implemented.
