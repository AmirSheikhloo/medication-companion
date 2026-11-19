import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'secure_backup_inspector.dart' show backedUpTables, schemaTemplate;

/// A bounded-memory, transaction-consistent representation of *logical* v5
/// contents. Only the digest and counts cross the isolate boundary; plaintext
/// rows, patient identifiers and per-record digests must never be logged.
final class LiveDatabaseFingerprint {
  final String sha256;
  final Map<String, int> counts;

  const LiveDatabaseFingerprint(this.sha256, this.counts);
}

/// Called at Phase A preview and, later, again while all writers are quiesced
/// behind the native exclusive Phase B DB-lifecycle lease. A mismatch MUST
/// abort before alarms, journal markers or the active DB are changed.
Future<LiveDatabaseFingerprint> fingerprintLiveDatabase(String path) =>
    Isolate.run(() => _fingerprint(path));

final _primaryKeys = <String, String>{
  for (final table in backedUpTables) table: 'id',
  'app_settings': 'key',
  'dose_current_states': 'occurrence_key',
  'stock_selections': 'medication_id',
  'stock_alert_rules': 'medication_id',
};

LiveDatabaseFingerprint _fingerprint(String path) {
  if (path.isEmpty || !File(path).isAbsolute ||
      FileSystemEntity.isLinkSync(path)) {
    throw const FormatException('Invalid live SQLite location');
  }
  final db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
  final collector = _SingleDigestSink();
  final sink = sha256.startChunkedConversion(collector);
  final encoder = _TypedDigestEncoder(sink);
  var committed = false;
  try {
    db.execute('PRAGMA query_only=ON');
    db.execute('PRAGMA busy_timeout=1500');
    // BEGIN supplies a single snapshot across metadata, all counts, all rows,
    // and the optional AUTOINCREMENT high-water mark table.
    db.execute('BEGIN');
    final version = db.select('PRAGMA user_version').single.values.single;
    if (version != 5) throw const FormatException('Not a live v5 database');

    final schema = db.select('SELECT type, name, tbl_name, sql FROM '
        'sqlite_master ORDER BY type, name');
    final signature = schemaTemplate(schema.map((row) => <String, Object?>{
      'type': row['type'], 'name': row['name'],
      'tbl_name': row['tbl_name'], 'sql': row['sql'],
    }));
    encoder.string('MC-LIVE-LOGICAL-V1');
    encoder.integer(5);
    for (final entry in signature) {
      encoder.string(entry);
    }
    // The schema entry stream itself is length-delimited.
    encoder.string('SCHEMA-END');

    final counts = <String, int>{};
    for (final table in backedUpTables) {
      final key = _primaryKeys[table]!;
      final columns = db.select('PRAGMA table_info("$table")');
      if (columns.isEmpty ||
          !columns.any((row) => row['name'] == key && row['pk'] == 1)) {
        throw const FormatException('Unrecognized live primary key');
      }
      final names = columns.map((row) => row['name'] as String).toList();
      encoder.string('TABLE');
      encoder.string(table);
      encoder.integer(names.length);
      for (final name in names) {
        encoder.string(name);
      }
      // Identifiers are fixed from our own v5 schema, never user-controlled.
      final statement = db.prepare(
          'SELECT * FROM "$table" ORDER BY "$key" COLLATE BINARY');
      var count = 0;
      try {
        final cursor = statement.selectCursor();
        while (cursor.moveNext()) {
          final row = cursor.current;
          if (row.values.length != names.length || row[key] is! String) {
            throw const FormatException('SQLite column shape changed');
          }
          encoder.string('ROW');
          for (final value in row.values) {
            encoder.value(value);
          }
          count++;
        }
      } finally {
        statement.close();
      }
      encoder.string('TABLE-END');
      encoder.integer(count);
      counts[table] = count;
    }

    final sequenceExists = db.select(
      "SELECT 1 FROM sqlite_master WHERE type='table' "
      "AND name='sqlite_sequence' LIMIT 1",
    ).isNotEmpty;
    encoder.string(sequenceExists ? 'SEQUENCE-PRESENT' : 'SEQUENCE-ABSENT');
    if (sequenceExists) {
      final statement = db.prepare(
          'SELECT name, seq FROM sqlite_sequence '
          'ORDER BY name COLLATE BINARY, typeof(seq), seq, rowid');
      try {
        final cursor = statement.selectCursor();
        while (cursor.moveNext()) {
          final name = cursor.current['name'];
          final sequence = cursor.current['seq'];
          if (name is! String || sequence is! int) {
            throw const FormatException('Invalid AUTOINCREMENT sequence');
          }
          encoder.string(name);
          encoder.integer(sequence);
        }
      } finally {
        statement.close();
      }
      encoder.string('SEQUENCE-END');
    }
    // Hash the state while the read snapshot is still held.
    sink.close();
    db.execute('COMMIT');
    committed = true;
    return LiveDatabaseFingerprint(collector.single.toString(), counts);
  } finally {
    if (!committed) {
      try { db.execute('ROLLBACK'); } catch (_) { /* preserve primary error */ }
    }
    db.close();
  }
}

final class _SingleDigestSink implements Sink<Digest> {
  Digest? _digest;
  Digest get single => _digest ?? (throw StateError('Digest not finalized'));

  @override
  void add(Digest value) {
    if (_digest != null) throw StateError('Digest emitted twice');
    _digest = value;
  }

  @override
  void close() {}
}

/// Each field has a one-byte type tag and a bounded 64-bit length/value,
/// preventing ambiguous concatenations, separator collisions, and type changes.
final class _TypedDigestEncoder {
  final Sink<List<int>> sink;
  _TypedDigestEncoder(this.sink);

  void _int64(int value) {
    final bytes = ByteData(8)..setInt64(0, value, Endian.big);
    sink.add(bytes.buffer.asUint8List());
  }

  void integer(int value) {
    sink.add(const <int>[1]);
    _int64(value);
  }

  void string(String value) {
    final bytes = utf8.encode(value);
    sink.add(const <int>[2]);
    _int64(bytes.length);
    sink.add(bytes);
  }

  void value(Object? value) {
    if (value == null) {
      sink.add(const <int>[0]);
    } else if (value is int) {
      integer(value);
    } else if (value is String) {
      string(value);
    } else if (value is double) {
      sink.add(const <int>[3]);
      final bytes = ByteData(8)..setFloat64(0, value, Endian.big);
      sink.add(bytes.buffer.asUint8List());
    } else if (value is Uint8List) {
      sink.add(const <int>[4]);
      _int64(value.length);
      sink.add(value);
    } else {
      throw const FormatException('Unsupported SQLite value type');
    }
  }
}
