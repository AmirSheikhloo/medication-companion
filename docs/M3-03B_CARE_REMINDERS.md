# M3-03B — Opt-in care reminders, recurring tasks and 3-month follow-ups

## Delivered

1. Local Android notifications for **visits**, **tasks**, and an optional **pre-visit checklist reminder** one calendar day before the appointment.
2. Reminder timing per item: at the event, 5/15/30/60 minutes before, or 24 hours before. A reminder setting on an item does **not** opt the user into OS notifications.
3. A separate master opt-in for care notifications. Permission checks include posting notifications and Android exact alarms, with explicit failure feedback.
4. Separate channel and managed notification-ID range `1510000000..2100000000`, disjoint from M0 IDs and M2 medicine range `1000000..1500999999`. Turning care reminders off must not affect medication alarms.
5. After any care mutation, the planner reconciles future alarms. On resume, enabled reminders are reconciled and OS-permission loss is exposed.
6. User-defined task repetition: daily, weekly, or monthly. Completing an occurrence appends an immutable `completed_cycle` event with previous due time and advances the task to the next due date. Month-end stays anchored to the selected day (e.g. Jan 31 → Feb 28 → Mar 31). A due date is required for repeat or OS reminder.
7. Manual "3-month follow-up" from an explicitly chosen reference date (for example the user's known course-end date); optional medication link is validated against the active profile. This **never stops, extends, or edits the medication itself**.
8. Drift **v5 additive migration**: old v1-v4 data is preserved; seven new nullable/defaulted care columns. The database filename is unchanged.

## Operational limits / honest UX

- This release is **Android only** and local demo only. Notifications are best-effort OS events, not proof of delivery or of actual medication usage.
- The scheduler places the next **eight** occurrences of each repeating task. It refreshes on app entry/resume and care mutations. If the app is not opened for a prolonged period, future occurrences beyond the current window are not guaranteed to have been scheduled.
- Exact alarms may be delayed or blocked by OS/vendor battery restrictions, and disabled permissions must be surfaced. Test physical Android devices before any real-world reliance.
- Notifications do not embed medication names or personal clinical details on the lock screen. Calendar-entry controls remain **Gregorian** pending the separate Persian-date workstream.
- A missed alarm or a dismissed notification does not modify the source database, task status, or medication schedule. No automatic medical advice is generated.

## CI gate

- Flutter analyze, all unit and widget tests, Android debug APK build.
- New tests: civil monthly arithmetic, deterministic noncolliding IDs, no silent opt-in, denied permission, independent care enable/disable, visit/checklist/task scheduling, completion reconciliation and action history, and direct v4→v5 migration.
- Existing v1→v5, v2→v5 and v3→v5 migration regressions continue to run.

## Manual emulator tests — stop at first failure

1. App upgrade retains previous medication, health, visit, task and checklist records.
2. Open Today → Care. Master care reminders are **off** before explicit user opt-in. A task with a reminder configured but no opt-in does not schedule an alert.
3. Enable "اعلان‌های پیگیری و ویزیت"; after permissions, use "تست اعلان پنج ثانیه‌ای". A separate care alert must arrive.
4. Create a task due ~3–5 minutes in the future; set reminder "در موعد". Put the emulator in background; the care alert should arrive at the due time. Mark done and confirm the alert is not rescheduled.
5. Create a visit for ~5–10 minutes ahead and choose a 5-minute reminder. Confirm an alert near that offset. Mark the visit completed; no new alert for the same visit should remain.
6. Create a daily repeating task due tomorrow with a reminder; mark it done. Its status remains open but its due date advances by one local calendar day; history adds `completed_cycle` without modifying any medication.
7. Create a month-end repeating task; complete one cycle and verify Feb/Mar month-end behavior as appropriate. A weekly task must move forward one week on completion.
8. From the visit tab choose "پیگیری سه ماه پس از تاریخ انتخابی"; set a reference date such as January 31. The follow-up date should be April 30 and no medication schedule changes.
9. Enable "یادآوری چک‌لیست یک روز قبل" on a future visit, save, reopen, verify the option persists. Its OS schedule is one calendar day earlier.
10. Turn **off care notifications** while leaving medication reminders enabled. Care demo must not run; previously scheduled medicine reminders must stay enabled.
11. Switch profiles; task/visit lists and related medication options remain private to the selected profile. Restart the app and verify settings and recurrence persist.

Do not change system clocks solely to simulate future medical notifications; test short-term alerts with test records. Always use fictitious data until encryption and backup are delivered.
