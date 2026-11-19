import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/features/backup/data/restore_read_only_preflight.dart';
import 'package:medication_companion/features/backup/data/secure_backup_inspector.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

const primaryKeys = <String, String>{
  'app_settings': 'key',
  'dose_current_states': 'occurrence_key',
  'stock_selections': 'medication_id',
  'stock_alert_rules': 'medication_id',
};

void createV5Fixture(String file) {
  final db = sqlite.sqlite3.open(file);
  try {
    db.execute('PRAGMA user_version = 5');
    for (final table in backedUpTables) {
      final pk = primaryKeys[table] ?? 'id';
      db.execute('CREATE TABLE "$table" '
          '("$pk" TEXT PRIMARY KEY, payload TEXT NOT NULL)');
    }
    db.execute("INSERT INTO profiles(id, payload) VALUES('p1','before')");
  } finally {
    db.close();
  }
}

void updateProfile(String file) {
  final db = sqlite.sqlite3.open(file);
  try {
    db.execute("UPDATE profiles SET payload='after' WHERE id='p1'");
  } finally {
    db.close();
  }
}

void main() {
  late Directory temp;
  late String live;
  late String candidate;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('m4-d4a-read-only-');
    live = '${temp.path}/live.sqlite';
    candidate = '${temp.path}/candidate.sqlite';
    createV5Fixture(live);
    createV5Fixture(candidate);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<RestoreReadOnlyPreviewEvidence> capture({
    Duration maxAge = const Duration(minutes: 5),
  }) => RestoreReadOnlyPreviewEvidence.captureReadOnly(
    liveDatabasePath: live,
    validatedCandidatePath: candidate,
    maxAge: maxAge,
  );

  Future<RestorePreviewRecheck> recheck(
      RestoreReadOnlyPreviewEvidence evidence) =>
    evidence.recheckReadOnly(
      liveDatabasePath: live,
      validatedCandidatePath: candidate,
    );

  test('stable live data and candidate remain read-only and unchanged', () async {
    final beforeLive = File(live).readAsBytesSync();
    final beforeCandidate = File(candidate).readAsBytesSync();
    final evidence = await capture();
    expect(await recheck(evidence), RestorePreviewRecheck.unchanged);
    expect(File(live).readAsBytesSync(), beforeLive);
    expect(File(candidate).readAsBytesSync(), beforeCandidate);
    evidence.invalidate();
  });

  test('same row count but a changed logical SQLite row is detected', () async {
    final evidence = await capture();
    updateProfile(live);
    expect(await recheck(evidence), RestorePreviewRecheck.liveDataChanged);
    evidence.invalidate();
  });

  test('altered candidate bytes of identical length are detected', () async {
    final evidence = await capture();
    final bytes = File(candidate).readAsBytesSync();
    bytes[bytes.length - 1] ^= 1;
    File(candidate).writeAsBytesSync(bytes, flush: true);
    expect(await recheck(evidence), RestorePreviewRecheck.candidateChanged);
    evidence.invalidate();
  });

  test('truncated candidate is detected', () async {
    final evidence = await capture();
    File(candidate).writeAsBytesSync([1, 2, 3], flush: true);
    expect(await recheck(evidence), RestorePreviewRecheck.candidateChanged);
  });

  test('missing candidate fails closed', () async {
    final evidence = await capture();
    File(candidate).deleteSync();
    expect(await recheck(evidence), RestorePreviewRecheck.cannotVerify);
  });

  test('missing live DB fails closed without creating a new DB', () async {
    final evidence = await capture();
    File(live).deleteSync();
    expect(await recheck(evidence), RestorePreviewRecheck.cannotVerify);
    expect(File(live).existsSync(), isFalse);
  });

  test('canceled preview cannot be re-used', () async {
    final evidence = await capture();
    evidence.invalidate();
    expect(await recheck(evidence), RestorePreviewRecheck.invalidated);
  });

  test('expired preview cannot be re-used', () async {
    final evidence = await capture(maxAge: const Duration(microseconds: 1));
    expect(await recheck(evidence), RestorePreviewRecheck.expired);
  });

  test('changing either input path cannot rebind previous evidence', () async {
    final evidence = await capture();
    expect(
      await evidence.recheckReadOnly(
        liveDatabasePath: live,
        validatedCandidatePath: '${temp.path}/other.sqlite',
      ),
      RestorePreviewRecheck.pathChanged,
    );
    expect(
      await evidence.recheckReadOnly(
        liveDatabasePath: '${temp.path}/other.sqlite',
        validatedCandidatePath: candidate,
      ),
      RestorePreviewRecheck.pathChanged,
    );
  });

  test('empty or identical source paths cannot generate evidence', () async {
    await expectLater(
      RestoreReadOnlyPreviewEvidence.captureReadOnly(
        liveDatabasePath: live,
        validatedCandidatePath: live,
      ),
      throwsArgumentError,
    );
    await expectLater(
      RestoreReadOnlyPreviewEvidence.captureReadOnly(
        liveDatabasePath: live,
        validatedCandidatePath: candidate,
        maxAge: Duration.zero,
      ),
      throwsArgumentError,
    );
  });
}
