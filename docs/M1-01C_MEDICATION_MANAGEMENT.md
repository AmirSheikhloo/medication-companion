# M1-01C — Offline medication management

This slice extends the already-tested M1 mobile UI. There are no new
dependencies, SQL columns, tables, or schema migrations. It reuses the existing
`MedicationPlanVersions` table and preserves all earlier local database rows.

## User-facing behavior

- A medication may have 1–12 different daily wall-clock times. Each time has
  its own free-text instructions, entered by the user, never AI-generated.
- Duplicate times, blank instructions, and invalid values are rejected.
- A medication can be renamed, and its times/instructions can be edited.
- Changes to the schedule become effective **the following local day**; today's
  dose events and keys remain unchanged.
- A repeated edit on the same day supersedes an earlier pending edit for
  tomorrow, without removing versions from the database.
- Archiving hides future dose cards and active medication listings. The archive
  list allows restoring a medication without deleting its history.
- A profile cannot edit or archive a medication belonging to another profile.

## Persistence contract

A schedule version is the group of immutable `MedicationPlanVersions` rows
sharing one `medicationId` and `version`. Each row is one wall-clock slot and
has its own `id`, text and time. All rows of a newly appended version share
`effectiveFrom`. Existing version-1 single-time rows remain valid. The active
version for a given day is the latest effective version; version 1 remains
the fallback for historical day lookups. An event refers to its slot's plan
ID via `OccurrenceKey`.

Every mutation is transactional; `DoseEvents` remain append-only.
Archiving is reversible and never deletes plan versions or recorded events.

**Known limitations:** A medication name edit is visible immediately, while
slot edits activate tomorrow. This M1 app has an unencrypted local database,
no migration/sync/cloud restore, and no automatic notification scheduling.
Use synthetic test data only. A future phase will add native reminders,
time-zone and reboot recovery, and encrypted storage/backup.

## Acceptance

1. Add a fictional medication with morning and evening slots and different
   descriptions. Today's tab shows two independent dose cards.
2. Mark one slot taken. The other remains pending. Undo the first.
3. Edit its name and schedule. The name updates immediately; today's recorded
   slots remain, while the new times apply tomorrow.
4. Archive and verify it disappears from today's and active medication lists;
   expand the archive list and restore it.
5. Switch profiles and verify medications cannot cross profile boundaries.
6. Close/reopen the app to confirm local persistence. Do not clear app data.

## Verification

CI runs `flutter pub get`, Drift generation, `flutter analyze` and
`flutter test`. Unit tests cover slot uniqueness, independent occurrences,
version selection, archived recovery, and profile isolation. Widget tests
operate the actual add/edit/archive/restore flow.
