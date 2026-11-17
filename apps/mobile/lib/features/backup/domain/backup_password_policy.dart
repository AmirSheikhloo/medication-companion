/// MCBK v1 uses the exact UTF-8 encoding of the entered passphrase.
/// Never normalize Unicode, trim a valid passphrase, or log its contents.
String? backupPasswordError(String password, String confirmation) {
  if (password.runes.length < 12 || password.trim().isEmpty) {
    return 'رمز باید دست‌کم ۱۲ نویسه داشته باشد و فقط فاصله نباشد.';
  }
  // Dart UTF-16 strings may contain an isolated surrogate; reject it so
  // UTF-8 cannot silently introduce replacement symbols.
  for (var i = 0; i < password.length; i++) {
    final unit = password.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= password.length ||
          password.codeUnitAt(i) < 0xdc00 ||
          password.codeUnitAt(i) > 0xdfff) {
        return 'رمز شامل نویسه نامعتبر است.';
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return 'رمز شامل نویسه نامعتبر است.';
    }
  }
  if (password != confirmation) return 'تکرار رمز با رمز اصلی یکسان نیست.';
  return null;
}
