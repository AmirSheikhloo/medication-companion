# Beta gate — estimated stock days, doctor PDF, seven-day dose log

This increment follows the approved UI mockups. The three additions are
offline-only conveniences; none recommends medication dosage or measures
clinical adherence. No database migration is required: user-entered daily
consumption estimates are stored as per-profile, per-medication, per-unit
settings. Existing data and installer behavior remain intact.

## Automated checks

- Estimate covers only the user-selected, non-expired package and requires
  an explicit positive daily quantity in that package's unit. Switching units
  does not convert or reuse quantities, and other profiles cannot mutate it.
- Seven-day log counts taken/skipped/unknown/pending separately, reflects
  undo, isolates profiles and does not invent pending doses on days before
  a medication was first created. Archived medication schedules are excluded.
- The offline Persian doctor-list PDF has the `%PDF-` header and rejects data
  mixed from other profiles. Its date denotes the displayed daily plan.
- Existing Flutter, installer, SQLite authorizer and APK checks remain green.

## Five focused emulator checks

1. **Stock estimate:** «داروها» > open a medication > «موجودی». Select a
   test package of 12 tablets and set «میانگین مصرف روزانه» to `2`. The sheet
   and compact list should show approximately **6 days**. Change to `3`,
   confirm **4 days**; clear the input and confirm the estimate disappears.
2. **No false conversion:** Add/select a second package with another unit,
   e.g. `ml`. The tablet-based estimate must disappear. Return to the tablet
   package and confirm the previous tablet estimate remains.
3. **Doctor PDF:** «داروها» > «فهرست داروها برای پزشک (PDF)» > confirm. The
   Android share sheet should open with a Persian PDF containing only the
   selected profile's active medicines, times and entered dose text. Cancel
   the confirmation and confirm no share sheet opens.
4. **Weekly log:** «امروز» > «گزارش ثبت مصرف در ۷ روز گذشته». Record a test
   dose as taken, another skipped, and try undo. Refresh the weekly report;
   counts and daily bars must follow the final recorded state. «ثبت‌نشده» is
   not called a medical missed dose.
5. **Regression glance:** Switch profiles, verify estimates and reports stay
   separate; scan 360x640 RTL at enlarged text; check old edit/archive/restore,
   reminder entry and beta CI number. Old previews are cleaned only following
   a successful new install.

No real patient data is needed. Real backup restoration, cloud features,
new notifications and public release are deliberately unchanged.
