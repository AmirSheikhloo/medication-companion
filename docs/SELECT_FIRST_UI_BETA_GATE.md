# Beta UI acceptance — select-first medication and inventory

This increment follows the user's CI112 feedback. The existing medication
schedule/stock ledger is unchanged; new preferences are scoped to one local
profile and medication via AppSettings. No data migration is needed.

## New behavior

- Medication entry/edit offers unit (عدد / ورق / بسته / دوز / سی‌سی) and
  quantity dropdowns. Dose explanation is optional; without it, a useful
  description is generated from the selectors. Legacy descriptions remain
  editable and are not automatically interpreted as numeric amounts.
- The preset per-medication debit quantity is shown in the Taken confirmation
  when its unit matches the selected stock package. The dialog uses selectable
  quantities, never free-form numeric entry. **No automatic conversion**
  between sheets, boxes, doses and individual tablets. A mismatch remains
  explicitly selectable only in the actual package unit.
- Stock creation has default labels (بسته اول, بسته دوم, ...), unit and
  initial-quantity dropdowns, and a native Persian date picker for expiry.
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
   quantity `20`; leave optional explanation empty. Confirm the medication
   saves and its schedule shows the chosen quantity.
2. In stock management, add two packages without names. Confirm «بسته اول» /
   «بسته دوم», select the corresponding unit, choose their quantities and
   optional expiry dates from the Persian calendar. Earliest expiry should
   appear first, un-dated packages last.
3. Tap «مصرف کردم». The dialog should offer **dropdown quantities** rather
   than keyboard entry. For a matching unit, it should preselect the saved
   amount. Verify the chosen deduction in stock history. Undo restores the
   exact movement.
4. Try a *different* default unit (e.g. «ورق») with an «عدد» stock package.
   It must not silently convert units. Confirm a visible message and package-
   unit selection; cancel or record without stock deduction if appropriate.
5. Export the Persian doctor-list PDF with several medicines containing ی، ک،
   نیم‌فاصله and numerals. Visually inspect letter joining, punctuation,
   order, word wrapping and sufficiently large type in a PDF viewer.
6. Trigger a deliberate validation failure (missing medication name or an
   adjustment exceeding remaining stock). A readable error should appear on
   the current screen. Check normal success feedback as well.

## Deferred polish

- Full Jalali localization of all remaining date/time selectors and labels.
- Additional picker presets and possible explicit **user-defined** conversion
  ratios for sheets/boxes, but never an inferred conversion.
- Consistent inline feedback across every route (not only medication/stock).
- Real backup restoration is still deferred, per product-owner direction.
