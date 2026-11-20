# Private Android MVP beta — acceptance gate

Updated: 2026-11-20. Scope: `feature/mobile-mvp-beta` (based on the read-only backup preview, M4-01C).

## Proven baseline and next beta increment

- CI105: all eight automated acceptance checks succeeded (GitHub Actions run 44783026354).
- User confirmed all six CI105 manual checks passed on the emulator.
- Next increment: remove M0 engineering entry code, add medicine search and today's status summary, identify build number in More, and automatically find the APK beside the bundled installer.
- The new increment must have a fresh green CI run; CI105 is evidence for the prior commit, not automatically for new changes.
- Required fresh manual checks: medicine search (including Persian letters), today's summary counts, visible CI build number, and installer auto-selection without a file dialog. Repeat old medication/backup tests only if a regression is observed.

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
