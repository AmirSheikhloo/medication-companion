# Beta UI acceptance — one-tap intake and selectable quantities

This increment covers the user's CI112–CI115 feedback. The existing medication
schedule/stock ledger is unchanged; new preferences are scoped to one local
profile and medication via AppSettings. No data migration is needed.

## New behavior

- Medication entry/edit offers selectable unit (عدد / ورق / بسته / دوز / سی‌سی)
  and a numeric keyboard for an exact user-entered amount. Dose explanation is
  optional; without it, a useful
  description is generated from the selectors. Legacy descriptions remain
  editable and are not automatically interpreted as numeric amounts.
- The per-medication debit quantity is entered once, when creating/editing the
  medication. **«مصرف کردم» records in one tap** and automatically deducts the
  preset amount from the selected package when it matches the package unit.
  There is no repeated quantity dialog. **No automatic conversion** between
  sheets, boxes, doses and individual tablets. An invalid/expired selection,
  missing preset, incompatible unit or insufficient balance blocks normal
  recording with a visible explanatory message and a stock-management shortcut.
  With no stock packages at all, medication tracking works without a debit;
  an explicit manual no-debit action remains in the three-dot menu when packages
  exist, alongside skipped/unknown, stock management and editing the preset.
- Stock creation has default labels (بسته اول, بسته دوم, ...), a selectable unit,
  a localized numeric input, and a native Persian date picker for expiry.
- Numeric input supports Latin, Arabic-Indic and Persian keyboards; the field
  immediately displays Persian digits and Persian decimal separator. Letters,
  signs, leading zeros and more than five integral/three fractional digits are
  rejected. Zero, incomplete or out-of-range values are rejected on submit.
  Optional daily-use/low-stock thresholds are disabled by leaving them blank.
- Packages display in earliest-expiry-first order; those without expiry come
  last. Manual adjustments/threshold changes remain available.
- Visible inline red errors and green success messages in the stock sheet;
  medication form validation is also visible in the sheet.
- Doctor-list PDF uses OpenType shaping for Persian/Arabic rather than relying
  on unshaped glyph text. A small Latin/punctuation fallback covers mixed
  medicine names, and unsupported symbols are shown as «نماد» instead of
  breaking the whole export. Larger type improves readability on a phone.

## Targeted emulator smoke

1. Create a new medication using only its **name**, select unit «سی‌سی» and
   type quantity `20` with the Latin keyboard; leave optional explanation empty.
   Confirm the field instantly displays «۲۰» and the medication
   saves and its schedule shows the chosen quantity.
2. In stock management, add two packages without names. Confirm «بسته اول» /
   «بسته دوم», select the corresponding unit, type their quantities and
   optional expiry dates from the Persian calendar. Earliest expiry should
   appear first, un-dated packages last.
3. Tap «مصرف کردم». **No dialog opens.** With a matching unit and selected
   package, the stored per-intake amount is automatically deducted. Verify in
   stock history; undo restores the exact original debit.
4. Try a *different* default unit (e.g. «ورق») with an «عدد» stock package.
   It must not silently convert units or mark the dose taken. Confirm a visible
   message and stock-management shortcut. The exceptional manual no-debit
   option is available under the dose card's three-dot menu.
5. Export the Persian doctor-list PDF with several medicines containing ی، ک،
   نیم‌فاصله and numerals. Visually inspect letter joining, punctuation,
   order, word wrapping and sufficiently large type in a PDF viewer.
6. Trigger a deliberate validation failure (missing medication name or an
   amount `0`, a letter, too many digits or an adjustment exceeding remaining
   stock). Letters should be blocked immediately and invalid values should
   show a readable error on
   the current screen. Check normal success feedback as well.

## Deferred polish

- Full Jalali localization of all remaining date/time selectors and labels.
- Additional picker presets and possible explicit **user-defined** conversion
  ratios for sheets/boxes, but never an inferred conversion.
- Consistent inline feedback across every route (not only medication/stock).
- Real backup restoration is still deferred, per product-owner direction.

## CI118+ comprehensive one-build smoke (15 checks)

1. Create a test medication with ۲٫۵ «عدد» per intake and multiple slots.
2. Confirm its draft and edit forms show the *automatic per-Taken deduction*.
3. Add two packages with generated default names and a matching «عدد» unit.
4. Give packages different expiry dates; check earliest-first ordering.
5. Explicitly select the first non-expired package and verify its balance.
6. On Today, confirm the preview says «کسر خودکار: ۲٫۵ عدد».
7. Tap «مصرف کردم» once; **no popup** appears and a success message appears.
8. Confirm exactly ۲٫۵ is deducted from the selected package, not the other.
9. Undo and confirm the same exact ۲٫۵ is credited back (no duplicate ledger).
10. Set a debit quantity greater than stock; Taken must fail visibly and stay pending.
11. Change the medicine preset unit to «ورق» while the package is «عدد»;
    Taken must fail visibly, with **no silent unit conversion**.
12. Open the three-dot menu. Select «مصرف نکردم», undo, then «مطمئن نیستم»;
    verify both statuses and reversibility.
13. With the unit mismatch, use the three-dot **manual no-debit** option.
    It records the dose without changing stock, with a distinct message.
14. Add a medicine without any stock packages; Taken must be one tap and
    record the dose without stock deduction or a popup.
15. Switch profiles, test Persian/Arabic/Latin numeric input, export the PDF,
    and check that the app remains responsive with seven medications.
