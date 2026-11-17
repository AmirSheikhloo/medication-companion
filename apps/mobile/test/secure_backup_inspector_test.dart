import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/features/backup/data/secure_backup_inspector.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late Directory sandbox;
  late File candidate;
  late BackupSchema baseline;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('m4-01c-inspector-');
    candidate = File('${sandbox.path}/candidate.sqlite');
    final db = sqlite.sqlite3.open(candidate.path);
    for (final table in backedUpTables) {
      db.execute('CREATE TABLE "$table" (id INTEGER PRIMARY KEY, value TEXT)');
    }
    db.execute('INSERT INTO profiles (id, value) VALUES (1, ?)', ['test']);
    db.userVersion = 5;
    baseline = schemaTemplate(db.select(
      'SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name',
    ).map((row) => <String, Object?>{
      'type': row['type'],
      'name': row['name'],
      'tbl_name': row['tbl_name'],
      'sql': row['sql'],
    }));
    db.close();
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  test('authenticated, exact v5 file is inspected read-only', () async {
    final original = candidate.readAsBytesSync();
    final counts = await inspectAuthenticatedBackup(candidate.path, baseline);
    expect(counts.length, 17);
    expect(counts['profiles'], 1);
    expect(counts['medications'], 0);
    expect(candidate.readAsBytesSync(), original);
  });

  test('unexpected view is rejected without execution', () async {
    final db = sqlite.sqlite3.open(candidate.path);
    db.execute('CREATE VIEW evil_view AS SELECT * FROM profiles');
    db.close();
    await expectLater(
      inspectAuthenticatedBackup(candidate.path, baseline),
      throwsA(isA<FormatException>()),
    );
  });

  test('unexpected table is rejected without execution', () async {
    final db = sqlite.sqlite3.open(candidate.path);
    db.execute('CREATE TABLE extra (value TEXT)');
    db.close();
    await expectLater(
      inspectAuthenticatedBackup(candidate.path, baseline),
      throwsA(isA<FormatException>()),
    );
  });

  test('old schema version is refused', () async {
    final db = sqlite.sqlite3.open(candidate.path);
    db.userVersion = 4;
    db.close();
    await expectLater(
      inspectAuthenticatedBackup(candidate.path, baseline),
      throwsA(isA<FormatException>()),
    );
  });

  test('an altered trusted schema baseline is rejected', () {
    final altered = [...baseline]..removeLast();
    expect(
      schemaTemplate([
        {'type': 'view', 'name': 'evil', 'tbl_name': 'evil', 'sql': 'SELECT 1'},
      ]),
      throwsFormatException,
    );
    expect(altered, isNot(baseline));
  });

  test('broken database header is rejected', () async {
    candidate.writeAsBytesSync(List<int>.filled(4096, 0));
    await expectLater(
      inspectAuthenticatedBackup(candidate.path, baseline),
      throwsA(anything),
    );
  });
}
