import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/features/backup/domain/mcbk_v1.dart';

void main() {
  Uint8List prefix({int length = 4096, int schema = 5}) =>
      McbkV1.buildPrefix(
        backupId: Uint8List.fromList(List.generate(16, (i) => i)),
        salt: Uint8List.fromList(List.generate(16, (i) => i + 16)),
        nonce: Uint8List.fromList(List.generate(12, (i) => i + 32)),
        createdUtcEpochMs: 1794910000000,
        plaintextLength: length,
        databaseSchemaVersion: schema,
      );

  UntrustedMcbkHeader parse(Uint8List b, {int? totalSize}) =>
      McbkV1.parsePrefix(
        b,
        actualFileSize: totalSize ?? McbkV1.overheadLength + 4096,
      );

  Uint8List changed(Uint8List original, int offset, int value) {
    final copy = Uint8List.fromList(original);
    copy[offset] = value;
    return copy;
  }

  test('layout offsets, approved KDF and complete AAD prefix', () {
    final b = prefix();
    expect(b.length, 105);
    expect(b.sublist(0, 4), [77, 67, 66, 75]);
    expect(b[4], 1);
    expect(b.sublist(5, 7), [0, 90]);
    expect(b.sublist(7, 28).last, 0);
    expect(b.sublist(28, 44), List.generate(16, (i) => i));
    expect(b.sublist(67, 83), List.generate(16, (i) => i + 16));
    expect(b.sublist(83, 95), List.generate(12, (i) => i + 32));
    expect(b.sublist(95, 97), [0, 0]);
    expect(b.sublist(97, 105), [0, 0, 0, 0, 0, 0, 16, 0]);
    final h = parse(b);
    expect(h.databaseSchemaVersion, 5);
    expect(h.ciphertextLength, 4096);
    expect(h.aad, b);
  });

  test('v1 through v5 source versions accepted; v0 and v6 rejected', () {
    for (var schema = 1; schema <= 5; schema++) {
      expect(parse(prefix(schema: schema)).databaseSchemaVersion, schema);
    }
    expect(() => parse(changed(prefix(), 55, 6)), throwsFormatException);
    expect(() => parse(changed(prefix(), 55, 0)), throwsFormatException);
  });

  test('strict file length, short prefix and cap boundaries', () {
    final b = prefix();
    expect(() => parse(b, totalSize: 121 + 4095), throwsFormatException);
    expect(() => parse(b, totalSize: 121 + 4097), throwsFormatException);
    expect(() => parse(b, totalSize: 0), throwsFormatException);
    expect(() => parse(Uint8List.fromList(b.sublist(0, 104))), throwsFormatException);
    expect(() => parse(Uint8List(106)), throwsFormatException);
    expect(
      () => McbkV1.buildPrefix(
        backupId: Uint8List(16),
        salt: Uint8List(16),
        nonce: Uint8List(12),
        createdUtcEpochMs: 1,
        plaintextLength: 67108865,
      ),
      throwsArgumentError,
    );
    final max = prefix(length: 67108864);
    expect(parse(max, totalSize: 121 + 67108864).ciphertextLength, 67108864);
  });

  test('high-bit and enormous uint64 values rejected before arithmetic', () {
    expect(() => parse(changed(prefix(), 97, 0x80)), throwsFormatException);
    expect(() => parse(changed(prefix(), 97, 0x7f)), throwsFormatException);
  });

  test('invalid magic, version, app ID, algorithm and flags reject', () {
    final b = prefix();
    for (final alteration in <(int, int)>[
      (0, 0), (4, 2), (6, 89), (7, 0), (27, 1),
      (56, 2), (57, 2), (96, 1),
    ]) {
      expect(() => parse(changed(b, alteration.$1, alteration.$2)), throwsFormatException);
    }
  });

  test('Argon2id profile must match an approved tuple exactly', () {
    final b = prefix();
    expect(() => parse(changed(b, 61, 65)), throwsFormatException);
    expect(() => parse(changed(b, 65, 4)), throwsFormatException);
    expect(() => parse(changed(b, 66, 2)), throwsFormatException);
  });

  test('timestamp validated before constructing a DateTime', () {
    final b = prefix();
    for (var offset = 44; offset <= 51; offset++) {
      b[offset] = 0xff;
    }
    expect(() => parse(b), throwsFormatException);
    expect(() => McbkV1.buildPrefix(
      backupId: Uint8List(16), salt: Uint8List(16), nonce: Uint8List(12),
      createdUtcEpochMs: 0, plaintextLength: 4096,
    ), throwsArgumentError);
  });

  test('caller mutation cannot change generated prefix', () {
    final id = Uint8List(16), salt = Uint8List(16), nonce = Uint8List(12);
    final p = McbkV1.buildPrefix(
      backupId: id, salt: salt, nonce: nonce,
      createdUtcEpochMs: 1, plaintextLength: 4096,
    );
    id[0] = 9; salt[0] = 8; nonce[0] = 7;
    expect(p[28], 0);
    expect(p[67], 0);
    expect(p[83], 0);
  });
}
