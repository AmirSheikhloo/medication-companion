# M2-01 — Opt-in local medication reminders (Android preview)

## Scope

Android medication reminders are independent of the M0 technical alarms.
This slice uses the already pinned `flutter_local_notifications` 23.0.2,
`flutter_timezone` and `timezone` dependencies. No new DB tables, schema
migration, or network connection is required.

- Disabled by default. The **More** tab includes explicit enable/disable
  controls and a **five-second test notification**.
- Android notification and exact alarm privileges are requested and checked
  before the app claims reminders are active. Revoked permissions surface an
  error on resynchronization.
- The scheduler reconciles **all** local profiles, not only the currently
  visible one.
- Existing daily plans are expanded into remaining *one-off* reminders for
  today and daily *recurring* reminders starting tomorrow. This allows a
  schedule edited today to switch over tomorrow without changing the current
  day's already-recorded dose identities.
- Taken/skipped/unknown occurrences are omitted from remaining one-off
  reminders on each app reconciliation.
- Adding/editing/archiving/restoring medications and changing a dose status
  trigger resynchronization. Opening the medications screen or resuming the app
  also triggers a permission-aware refresh.
- Only notifications inside M2's reserved notification ID range are
  cancelled/replaced, leaving M0 test IDs **101/202** untouched.
- Lockscreen visibility is private and normal notifications never request a
  full-screen intent. Tapping a notification is informational; it never
  silently records that a medication was taken.
- At most **120** pending managed jobs are allowed in this preview to prevent
  uncontrolled OS alarm consumption. Exceeding the cap reports an error.

## Offline & restart

The existing plugin receivers handle OS-side rescheduling after reboot and
app package replacement. Persisted opt-in is in `AppSettings`, not global
prefs. On entry or app resume the active OS schedule is reconciled from the
offline Drift database and the phone's time zone.

## Important limitations and gates

This is a technical preview, **not** a medically validated reminder system.
Reliable precise delivery can vary with OEM battery policies, Doze,
Android permission revocation, OS restarts and timezone changes while the app
is not opened. In particular, changed timezone/permission state needs
on-device testing; pending scheduled notifications may not automatically
reconcile until the medications screen is opened again. Do not use production
medical data while the local DB is unencrypted and backup is absent.
A notification is not evidence that a dose was taken.

The short five-second demo *only* schedules a clearly labeled synthetic
notification. It never changes medication schedule times or intervals.

## Manual acceptance (Android emulator and physical phone)

1. Open an existing synthetic profile, then More -> enable reminders. If the
   OS requests notification and exact alarm permissions, grant both. Verify
   the status shows enabled; denied permissions must not claim success.
2. Tap **Test notification — 5 seconds**; verify one ordinary notification
   appears without opening a full-screen activity.
3. Add a synthetic medication with a wall-clock time several minutes ahead
   and confirm the actual saved-time reminder arrives with the device app
   backgrounded. This test should not instruct any real medication use.
4. Mark an upcoming dose taken or archive its medication before the alarm:
   its old pending reminder should be removed on reconciliation.
5. Close the app, reopen it and verify opt-in and medication/profile data
   persist. Test reboot behavior separately on the physical Android 14 phone.
6. Turn reminders off; verify managed reminders are cancelled and M0
   5s/10s diagnostics remain usable independently.

## Automated tests

- Pure planner covers stable IDs, split today/tomorrow schedules, suppressing
  recorded occurrences and capacity limits.
- Fake notification port covers opt-in/denial, profile enumeration, status
  reconciliation, edits, archive/restore, demo isolation and disable.
- Widget acceptance covers the actual More tab controls.
- GitHub CI runs `flutter analyze` and `flutter test`.
