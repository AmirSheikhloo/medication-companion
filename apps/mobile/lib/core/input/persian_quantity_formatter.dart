import 'package:flutter/services.dart';

/// Keeps numeric editing predictable across Latin, Arabic and Persian keyboards.
/// Numbers are displayed with Persian digits immediately, not just on save.
/// A temporary ۰ is permitted while entering a fraction such as ۰٫۵; callers
/// must reject zero and incomplete values when submitting.
class PersianQuantityFormatter extends TextInputFormatter {
  const PersianQuantityFormatter();

  static const int maxMilliunits = 99999999;

  static final RegExp _partialQuantity = RegExp(
    r'^(?:$|(?:۰|[۱-۹][۰-۹]{0,4})(?:٫[۰-۹]{0,3})?)$',
  );

  static String display(String input) => String.fromCharCodes([
        for (final rune in input.runes)
          if (rune >= 0x30 && rune <= 0x39)
            rune - 0x30 + 0x06F0
          else if (rune >= 0x0660 && rune <= 0x0669)
            rune - 0x0660 + 0x06F0
          else if (rune == 0x002E)
            0x066B
          else
            rune,
      ]);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = display(newValue.text);
    if (!_partialQuantity.hasMatch(normalized)) return oldValue;
    return newValue.copyWith(
      text: normalized,
      composing: TextRange.empty,
    );
  }
}
