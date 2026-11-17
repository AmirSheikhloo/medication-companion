# M3-04 — Local Beta: Persian date entry and expanded notifications

## Scope and safety

- No database schema change, migration, data wipe, new account, network access, or prescription logic.
- Medication dose times, health measurement times, and follow-up times remain local Gregorian `DateTime` values as before. The Jalali conversion is strictly at the input/display boundary.
- Care, health observations, and exact-day inventory expiry support manual Jalali dates (Persian, Arabic or Latin digits). The Gregorian system calendar remains available in the same dialog.
- **Important:** inventory expiry precision `month` still refers to a **Gregorian** calendar month, exactly as the existing repository did. The UI now explicitly labels this. A future data-model upgrade is required for Persian-month precision; silently changing its meaning would corrupt existing semantics.
- The Android notification text uses `BigTextStyleInformation`, which supports expandable notifications. Android controls the compact heads-up height; full multiline text is visible only when expanded, not guaranteed in the initial banner.
- Text inputs have not been ASCII-restricted in Dart. On an Android Emulator, Persian letters require installing/enabling Persian in the on-screen/physical keyboard settings; the application cannot add a keyboard language to Android.

## Automated gate

1. `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`, `flutter analyze`, `flutter test`, `flutter build apk --debug` in CI.
2. Civil-calendar tests cover three Nowruz anchors, leap Esfand, invalid dates, Arabic/Persian/Latin digits, 1900–2100 Gregorian month starts and ends, and time-of-day preservation.
3. Dialog widget tests cover valid Jalali selection and invalid Esfand input.
4. Existing care reminders, medications, stock and health suites must continue passing.

## Minimal manual acceptance checks

1. **Care / Tasks:** Open `پیگیری‌ها` > `کارها` > `کار جدید` > date row. Enter `۱۴۰۵/۰۱/۰۱` > `تأیید تاریخ`, choose the time and save. Expected: displayed Jalali date `۱۴۰۵/۰۱/۰۱`, no date shifted by one day. Repeat by choosing `انتخاب از تقویم میلادی` instead.
2. **Care / Visits:** Open `ویزیت‌ها` > new visit > date row. Enter `۱۴۰۴/۱۲/۳۰` and confirm. Expected: visible validation error (1404 is not a leap year); dialog remains open. Enter `۱۴۰۳/۱۲/۳۰` and confirm; expected successful date selection.
3. **Health:** Open health measurements > add observation > date button. Enter a Jalali date within the permitted past range; verify both Jalali and Gregorian dates before saving, then check the record.
4. **Inventory:** Open medication > packages > add package > expiry date. Pick an exact Jalali expiry day. Check the displayed date. If changing precision to `فقط ماه و سال`, check the explicit **Gregorian-month** wording before saving.
5. **Notifications:** In `پیگیری‌ها` > `اعلان‌های پیگیری و ویزیت`, use the 5-second test notification. When the notification arrives, expand it using the system arrow/gesture. Expected: full multiline body visible expanded; the initial floating banner may still truncate it due to Android's own compact layout.
6. **Persian keyboard:** Attempt Persian text in a care-task title or medication name. If only English keys appear, enable Persian for the emulator's keyboard (`Settings` > `System` > `Keyboard` > `On-screen keyboard` > `Gboard` > `Languages`). This is an emulator configuration prerequisite, not a Flutter text filter.

If any check fails, stop at that check and send its number, exact screen, and screenshot/log. No need to repeat already-passing historical medication reminder suites.
