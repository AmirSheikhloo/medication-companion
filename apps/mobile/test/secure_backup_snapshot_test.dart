import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/features/backup/data/secure_backup_snapshot.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late Directory sandbox;
  late File source;
  late File target;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('m4-01b-vacuum-');
    source = File('${sandbox.path}/live.db');
    target = File('${sandbox.path}/snapshot.db');
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  test('bound read-only snapshot preserves committed uncheckpointed WAL', () async {
    final db = sqlite.sqlite3.open(source.path);
    try {
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA wal_autocheckpoint=0');
      db.execute('CREATE TABLE medications (id INTEGER PRIMARY KEY, name TEXT)');
      db.execute("INSERT INTO medications (name) VALUES ('synthetic test')");
      db.userVersion = 5;
      expect(File('${source.path}-wal').existsSync(), isTrue);

      await createReadOnlySnapshot(source.path, target.path);
      expect(target.existsSync(), isTrue);
      final copy = sqlite.sqlite3.open(target.path, mode: sqlite.OpenMode.readOnly);
      try {
        expect(copy.userVersion, 5);
        expect(copy.select('SELECT COUNT(*) AS n FROM medications').single['n'], 1);
        expect(copy.select('PRAGMA integrity_check').single.values.single, 'ok');
      } finally {
        copy.close();
      }
      expect(db.select('SELECT COUNT(*) AS n FROM medications').single['n'], 1);
    } finally {
      db.close();
    }
  });

  test('existing populated target is never overwritten', () async {
    final db = sqlite.sqlite3.open(source.path);
    db.execute('CREATE TABLE t (id INTEGER)');
    db.close();
    target.writeAsStringSync('do not replace');
    await expectLater(
      createReadOnlySnapshot(source.path, target.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(target.readAsStringSync(), 'do not replace');
  });

  test('missing source never creates a target', () async {
    await expectLater(
      createReadOnlySnapshot(source.path, target.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(target.existsSync(), isFalse);
  });
}
