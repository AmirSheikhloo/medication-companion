import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/features/backup/data/live_database_fingerprint.dart';
import 'package:medication_companion/features/backup/data/secure_backup_inspector.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

const _nonstandardKeys = <String, String>{
  'app_settings': 'key',
  'dose_current_states': 'occurrence_key',
  'stock_selections': 'medication_id',
  'stock_alert_rules': 'medication_id',
};

void initializeFixture(String path, {bool withSequence = false}) {
  final db = sqlite.sqlite3.open(path);
  try {
    db.execute('PRAGMA user_version=5');
    for (final table in backedUpTables) {
      final key = _nonstandardKeys[table] ?? 'id';
      db.execute('CREATE TABLE "$table" '
          '("$key" TEXT PRIMARY KEY, payload BLOB, reading REAL, note TEXT)');
    }
    if (withSequence) {
      // After dropping the AUTOINCREMENT table, SQLite retains the internal
      // sqlite_sequence table, without an unexpected app table in our schema.
      db.execute('CREATE TABLE temporary_sequence_seed '
          '(id INTEGER PRIMARY KEY AUTOINCREMENT)');
      db.execute('DROP TABLE temporary_sequence_seed');
      db.execute("INSERT INTO sqlite_sequence(name, seq) VALUES('counter', 7)");
    }
  } finally {
    db.close();
  }
}

void insertRow(String path, String table, String key, {String? note}) {
  final db = sqlite.sqlite3.open(path);
  try {
    final column = _nonstandardKeys[table] ?? 'id';
    db.execute('INSERT INTO "$table" '
        '("$column", payload, reading, note) VALUES (?, ?, ?, ?)',
        [key, <int>[0, 255, 1], 0.125, note]);
  } finally {
    db.close();
  }
}

void main() {
  late Directory temp;
  late String path;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('m4-live-fingerprint-');
    path = '${temp.path}/live.sqlite';
    initializeFixture(path);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('17-table snapshot includes deterministic counts and has no sqlite_sequence dependency', () async {
    insertRow(path, 'profiles', 'p1');
    insertRow(path, 'medications', 'm1');
    final first = await fingerprintLiveDatabase(path);
    final second = await fingerprintLiveDatabase(path);
    expect(first.sha256, hasLength(64));
    expect(first.sha256, second.sha256);
    expect(first.counts.length, 17);
    expect(first.counts['profiles'], 1);
    expect(first.counts['medications'], 1);
    expect(first.counts['dose_events'], 0);
  });

  test('same counts but altered contents invalidate prior consent', () async {
    insertRow(path, 'profiles', 'p1', note: 'original');
    final before = await fingerprintLiveDatabase(path);
    final db = sqlite.sqlite3.open(path);
    try {
      db.execute('UPDATE profiles SET note = ? WHERE id = ?',
          ['changed', 'p1']);
    } finally {
      db.close();
    }
    final after = await fingerprintLiveDatabase(path);
    expect(after.counts, before.counts);
    expect(after.sha256, isNot(before.sha256));
  });

  test('insertion order does not change logical fingerprint', () async {
    final other = '${temp.path}/other.sqlite';
    initializeFixture(other);
    insertRow(path, 'profiles', 'z');
    insertRow(path, 'profiles', 'a');
    insertRow(other, 'profiles', 'a');
    insertRow(other, 'profiles', 'z');
    expect((await fingerprintLiveDatabase(path)).sha256,
        (await fingerprintLiveDatabase(other)).sha256);
  });

  test('VACUUM changes physical pages but not the logical-data digest', () async {
    insertRow(path, 'profiles', 'p1');
    insertRow(path, 'medications', 'm1');
    final before = await fingerprintLiveDatabase(path);
    final db = sqlite.sqlite3.open(path);
    try {
      db.execute('VACUUM');
    } finally {
      db.close();
    }
    final after = await fingerprintLiveDatabase(path);
    expect(after.sha256, before.sha256);
    expect(after.counts, before.counts);
  });

  test('AUTOINCREMENT high-water mutations are detected without row changes', () async {
    final withSequence = '${temp.path}/with-sequence.sqlite';
    initializeFixture(withSequence, withSequence: true);
    final before = await fingerprintLiveDatabase(withSequence);
    final db = sqlite.sqlite3.open(withSequence);
    try {
      db.execute("UPDATE sqlite_sequence SET seq = 8 WHERE name = 'counter'");
    } finally {
      db.close();
    }
    final after = await fingerprintLiveDatabase(withSequence);
    expect(after.counts, before.counts);
    expect(after.sha256, isNot(before.sha256));
    expect(after.sha256, isNot((await fingerprintLiveDatabase(path)).sha256));
  });

  test('incorrect user_version is rejected rather than interpreted', () async {
    final db = sqlite.sqlite3.open(path);
    try {
      db.execute('PRAGMA user_version=4');
    } finally {
      db.close();
    }
    await expectLater(fingerprintLiveDatabase(path), throwsFormatException);
  });
}
