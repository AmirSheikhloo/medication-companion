import 'dart:typed_data';

/// MCBK v1 framing only. This file intentionally performs NO encryption,
/// password derivation or SQLite I/O. Header fields remain UNTRUSTED until
/// the caller verifies the AES-256-GCM authentication tag over all 105 AAD
/// bytes and the complete ciphertext.
final class McbkV1 {
  McbkV1._();

  static const int headerLength = 90;
  static const int aadLength = 105;
  static const int overheadLength = 121;
  static const int minimumPayloadLength = 4096;
  static const int maximumPayloadLength = 67108864;
  static const int schemaVersion = 5;

  static const List<int> _magic = [0x4d, 0x43, 0x42, 0x4b];
  static const List<int> _appId = [
    109, 101, 100, 105, 99, 97, 116, 105, 111, 110, 45,
    99, 111, 109, 112, 97, 110, 105, 111, 110, 0,
  ];

  /// Explicitly untrusted metadata; do not display/interpret as verified.
  static UntrustedMcbkHeader parsePrefix(
    Uint8List prefix, {
    required int actualFileSize,
  }) {
    if (actualFileSize < overheadLength + minimumPayloadLength ||
        actualFileSize > overheadLength + maximumPayloadLength) {
      throw const FormatException('MCBK length outside permitted bounds');
    }
    if (prefix.length != aadLength) {
      throw const FormatException('MCBK requires exactly 105 prefix bytes');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (prefix[i] != _magic[i]) {
        throw const FormatException('Invalid MCBK magic');
      }
    }
    if (prefix[4] != 1 || _u16(prefix, 5) != headerLength) {
      throw const FormatException('Unsupported MCBK envelope version');
    }
    for (var i = 0; i < _appId.length; i++) {
      if (prefix[7 + i] != _appId[i]) {
        throw const FormatException('Unexpected MCBK app identifier');
      }
    }
    if (prefix[56] != 1 || prefix[57] != 1) {
      throw const FormatException('Unsupported encryption or KDF');
    }
    if (_u16(prefix, 95) != 0) {
      throw const FormatException('Unsupported MCBK flags');
    }

    // Reject unsigned 64-bit values with the sign bit set BEFORE arithmetic.
    if ((prefix[97] & 0x80) != 0) {
      throw const FormatException('Invalid unsigned ciphertext length');
    }
    final payloadLength = _u64(prefix, 97);
    if (payloadLength < minimumPayloadLength ||
        payloadLength > maximumPayloadLength ||
        actualFileSize != overheadLength + payloadLength) {
      throw const FormatException('Invalid MCBK ciphertext length');
    }

    final epochMs = _i64(prefix, 44);
    if (epochMs < 1 || epochMs > 8640000000000000) {
      throw const FormatException('Invalid MCBK timestamp');
    }

    final schema = _u32(prefix, 52);
    if (schema < 1 || schema > schemaVersion) {
      throw const FormatException('Unsupported MCBK schema');
    }

    final memoryKiB = _u32(prefix, 58);
    final iterations = _u32(prefix, 62);
    final parallelism = prefix[66];
    // Absolute caps are an additional defense, not approval of all tuples.
    if (memoryKiB < 19456 ||
        memoryKiB > 262144 ||
        iterations < 2 ||
        iterations > 20 ||
        parallelism < 1 ||
        parallelism > 4 ||
        memoryKiB != 65536 ||
        iterations != 3 ||
        parallelism != 1) {
      throw const FormatException('Unapproved MCBK Argon2id profile');
    }
    return UntrustedMcbkHeader._(
      Uint8List.fromList(prefix),
      Uint8List.fromList(prefix.sublist(28, 44)),
      Uint8List.fromList(prefix.sublist(67, 83)),
      Uint8List.fromList(prefix.sublist(83, 95)),
      epochMs,
      schema,
      payloadLength,
    );
  }

  /// Builds AAD; must be followed by a genuinely incremental, authenticated
  /// AES-GCM implementation before any file is published as a backup.
  static Uint8List buildPrefix({
    required Uint8List backupId,
    required Uint8List salt,
    required Uint8List nonce,
    required int createdUtcEpochMs,
    required int plaintextLength,
    int databaseSchemaVersion = schemaVersion,
  }) {
    if (backupId.length != 16 || salt.length != 16 || nonce.length != 12) {
      throw ArgumentError('Invalid backup ID, salt or nonce length');
    }
    if (createdUtcEpochMs < 1 ||
        createdUtcEpochMs > 8640000000000000 ||
        databaseSchemaVersion < 1 ||
        databaseSchemaVersion > schemaVersion ||
        plaintextLength < minimumPayloadLength ||
        plaintextLength > maximumPayloadLength) {
      throw ArgumentError('Invalid MCBK header parameter');
    }
    final out = Uint8List(aadLength);
    out.setRange(0, 4, _magic);
    out[4] = 1;
    _writeU16(out, 5, headerLength);
    out.setRange(7, 28, _appId);
    out.setRange(28, 44, backupId);
    _writeU64(out, 44, createdUtcEpochMs);
    _writeU32(out, 52, databaseSchemaVersion);
    out[56] = 1;
    out[57] = 1;
    _writeU32(out, 58, 65536);
    _writeU32(out, 62, 3);
    out[66] = 1;
    out.setRange(67, 83, salt);
    out.setRange(83, 95, nonce);
    _writeU16(out, 95, 0);
    _writeU64(out, 97, plaintextLength);
    return out;
  }

  static int _u16(Uint8List b, int start) =>
      ByteData.sublistView(b).getUint16(start, Endian.big);
  static int _u32(Uint8List b, int start) =>
      ByteData.sublistView(b).getUint32(start, Endian.big);
  static int _u64(Uint8List b, int start) =>
      ByteData.sublistView(b).getUint64(start, Endian.big);
  static int _i64(Uint8List b, int start) =>
      ByteData.sublistView(b).getInt64(start, Endian.big);
  static void _writeU16(Uint8List b, int start, int value) =>
      ByteData.sublistView(b).setUint16(start, value, Endian.big);
  static void _writeU32(Uint8List b, int start, int value) =>
      ByteData.sublistView(b).setUint32(start, value, Endian.big);
  static void _writeU64(Uint8List b, int start, int value) =>
      ByteData.sublistView(b).setUint64(start, value, Endian.big);
}

final class UntrustedMcbkHeader {
  UntrustedMcbkHeader._(
    this.aad,
    this.backupId,
    this.salt,
    this.nonce,
    this.createdUtcEpochMs,
    this.databaseSchemaVersion,
    this.ciphertextLength,
  );

  /// Never treat these fields as authenticated until the GCM tag passes.
  final Uint8List aad;
  final Uint8List backupId;
  final Uint8List salt;
  final Uint8List nonce;
  final int createdUtcEpochMs;
  final int databaseSchemaVersion;
  final int ciphertextLength;
}
