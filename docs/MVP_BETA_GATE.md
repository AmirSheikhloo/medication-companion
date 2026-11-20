# Private Android MVP beta — acceptance gate

Updated: 2026-11-20. Scope: `feature/mobile-mvp-beta` (based on the read-only backup preview, M4-01C).

## Proven baseline and next beta increment

- CI105: all eight automated acceptance checks succeeded (GitHub Actions run 44783026354).
- User confirmed all six CI105 manual checks passed on the emulator.
- Next increment: remove M0 engineering entry code, add medicine search and today's status summary, identify build number in More, and automatically find the APK beside the bundled installer.
- The new increment must have a fresh green CI run; CI105 is evidence for the prior commit, not automatically for new changes.
- Required fresh manual checks: medicine search (including Persian letters), today's summary counts, visible CI build number, and installer auto-selection without a file dialog. Repeat old medication/backup tests only if a regression is observed.
- Persian entry acceptance: a Persian name pasted into a medicine/profile field must remain unchanged. Input fields have no ASCII-only formatters. If physical typing yields English only, add Persian to the Android emulator Gboard language list; beta's More tab offers a one-tap shortcut to input-method language settings. On a hardware-keyboard AVD, enable the on-screen keyboard under Physical keyboard settings. Keyboard language is selected by Android, not forced by the Flutter app.

## UI polish acceptance (beta 0.3.0)

The previous CI108 passed automated checks, and the user confirmed all four new UI/manual checks passed. The next iteration must have its own CI proof.

- Register bundled NotoSansArabic regular/bold as the default text font, with high-contrast dark teal action surfaces.
- Responsive profile/welcome screens: short viewports and increased text sizes must scroll without RenderFlex overflow.
- Medicine cards grow with schedule details, keep edit/stock/archive menu, and wrap long stock and medication text.
- Today's summary includes an understandable completion indicator and an add-medicine shortcut.
- CI widget tests explicitly cover 360×640 logical pixels and 1.3–1.4 text scaling.
- Smoke manually on CI109: first-run welcome, long-name medicine card, Today's summary, and version display. Don't repeat CI105/CI108 historical tests without a regression signal.

## Product decision

Ship a compact, **offline single-device beta** now. Postpone real encrypted-backup restoration. Keep encrypted export and read-only authentication/inspection. Do not enable a partial restore implementation or imply users can restore erased data.

## Must pass in CI before handing out an APK

- [ ] Flutter 3.50 dependency resolution and Android API 37 `path_provider_android=2.2.23` guard
- [ ] Drift code generation
- [ ] `flutter analyze`
- [ ] `flutter test`, including entry-route, startup retry, Persian medicine search and status summary smoke tests
- [ ] PowerShell installer `-SelfTest` (older previews only, keep unrelated/newer apps, APK auto-discovery)
- [ ] Debug APK built with `MVP_BETA=true`
- [ ] Android SQLite authorizer exports
- [ ] APK and installer uploaded together

## One-pass manual emulator acceptance

1. **Identity/startup:** Install using bundled PowerShell script. App labeled `همراه دارو (بتا N)` opens directly to profile/medication workspace, not `آزمون M0`. Only the newly installed beta preview should remain from the older `.m4rNNN` series after successful installation.
2. **Persistence:** Create a test profile, one medicine and dose schedule; close and reopen the **same build**. All data remains.
3. **Doses/inventory:** Mark one dose taken, add a stock package and record a stock movement; verify the new totals.
4. **Reminder:** Open `بیشتر`, enable reminder permissions as requested and trigger the 5-second test notification. Verify the banner appears, subject to Android notification settings.
5. **Profiles and care:** Add and switch a managed profile; open the care/visit checklist. Entries must not leak between profiles.
6. **Health:** Record a sample health measurement; navigate away and back, and confirm persistence.
7. **Backup, read-only:** Create an encrypted backup with a test password, select it for inspection with the correct password, verify counts. Wrong password must fail. **No restore button or database replacement should be available.**
8. **No-surprises check:** Exit/relaunch after the above and check errors, empty screens, duplicates, RTL readability and Android overflow banners.

Send a screenshot + exact error message for failed gates; do not run destructive cleanup manually. Use synthetic data only.

## Deferred deliberately

- Import/restore transaction, recovery after power loss/process kill, and full restoration UX
- Stable signed `applicationId` upgrade chain; hosted CI builds use isolated IDs and ephemeral debug signing
- Account/cloud sync/admin UI, cross-device data migration, backups recoverable after uninstall
- Public distribution, clinical-grade reminder reliability and production app-store release

## Risk and promotion

Local data may be lost when a CI preview is uninstalled. Even a good encrypted export **cannot be restored with this beta**. This is acceptable only for disposable test records. Before public release: configure persistent signing securely, use a stable package name, complete release QA on physical devices and revisit local-data recovery, accessibility and notification behavior.

## Progress convention

Report **beta acceptance** as completed items from the eight CI gates above, plus the manual gates separately. Do not reuse the earlier M4-01D twelve-step restore score as a beta-release metric.
