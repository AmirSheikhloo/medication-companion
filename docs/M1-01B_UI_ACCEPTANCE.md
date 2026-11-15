# M1-01B — Mobile UI integration

The existing M0 alarm and PDF diagnostic app remains the launch screen.
A new entry button **«ورود به بخش داروهای من»** opens the M1 profile and
medication screens. The existing M0 functions and short alarm test timings
are not modified.

## Available now
- Local guest onboarding for yourself or someone you care for.
- Selection of active local profile; medications remain scoped to profile.
- One daily schedule per medication, entered **only as stated by the user**.
- Today's doses with “taken”, “skipped”, “unsure” and append-only undo.
- Offline data stored in Drift SQLite; no online account or admin dependency.
- Dedicated, separate repository and presentation files; M0 stays available.

## Not yet available
- Real medication reminders driven by the entered schedules.
- Backup, encryption at rest, online sync, account security or export.
- Inventory and reporting. The existing sample PDF still has a known
  Persian character-shaping issue and is intentionally deferred.

**Demo data only.** The local SQLite database is not yet encrypted. Do not
enter real medical or personal information in this release.

## Phone acceptance test (Samsung A52s)
1. From the M0 screen tap **«ورود به بخش داروهای من»**.
2. Choose **«برای خودم»**; a local profile should open.
3. Go to **«داروها»**, add one fictional drug and a daily time.
4. Open **«امروز»**; mark the dose as taken, then undo. Status returns to
   pending while the history remains.
5. Add a second *fictional* managed profile from **«بیشتر»**, switch to it,
   and verify the first profile's medication is not shown.
6. Press Android Back to return to M0; check the notification and PDF test
   buttons still exist. Do not repeat long waits unless specifically needed.
7. Close and reopen the app; the selected profile and demo drug remain.

CI: Dart code generation, analyzer, repository/domain tests, onboarding widget
smoke test, and the existing M0 widget test must all pass.
