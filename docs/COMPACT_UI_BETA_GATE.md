# Compact medication UI — beta acceptance (design phase 1)

This increment implements the approved lighter visual foundation and compact
medication management list. It does **not** add new medical, reminder, storage,
backup-restore, or account functionality.

## Automated gate

- Flutter analyze and the complete existing Flutter test suite remain green.
- The new compact-medications widget test verifies seven Persian medication
  rows, single expanded detail at a time, and the low-stock filter.
- Prior widget tests still cover Persian search normalization, medication
  add/edit/archive/restore, narrow screens, and the beta entry route.
- The existing Android beta APK, SQLite authorizer, and installer self-test
  remain mandatory in the Mobile CI workflow.

## Manual emulator smoke — one pass on the new APK

1. **Seven-medication scan:** Open «داروها» with seven test entries. Verify
   rows are compact, readable, and do not require scrolling through seven
   full-size cards. Confirm long Persian names wrap or truncate safely.
2. **Details on demand:** Tap two different rows. Only the chosen drug should
   show full scheduled doses, selected-package stock, and edit/stock actions.
   The three-dot menu must still work.
3. **Filters and search:** Try «همه», «کم‌موجودی», «بایگانی»; search with
   Persian letters, including ی/ي and ک/ك variants. An empty result must
   present an understandable message.
4. **Existing workflows:** Add and edit a medication, archive it, restore it,
   and open stock management. Use synthetic data only.
5. **Context and accessibility:** Switch profiles, verify each profile's
   medication list stays separate, and spot-check a 360x640 screen at
   enlarged font scale. Check RTL alignment, tap targets and overflow.
6. **Regression glance:** Visit «امروز», «سلامت» and «بیشتر». Check the
   reminder test button and beta CI number still exist. This is a smoke
   check, not a requirement to rerun every old manual gate.

**Explicitly out of scope:** new convenience features awaiting user approval,
real backup restoration, online accounts/sync, public production deployment.
