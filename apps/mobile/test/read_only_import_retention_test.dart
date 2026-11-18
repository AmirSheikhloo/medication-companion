import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/features/backup/data/read_only_import_retention.dart';
import 'package:medication_companion/features/backup/data/restore_read_only_preflight.dart';
import 'package:medication_companion/features/backup/data/secure_backup_inspector.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

const _keys = <String, String>{
  'app_settings': 'key',
  'dose_current_states': 'occurrence_key',
  'stock_selections': 'medication_id',
  'stock_alert_rules': 'medication_id',
};

void _fixture(String path) {
  final db = sqlite.sqlite3.open(path);
  try {
    db.execute('PRAGMA user_version=5');
    for (final name in backedUpTables) {
      final key = _keys[name] ?? 'id';
      db.execute('CREATE TABLE "$name" '
          '("$key" TEXT PRIMARY KEY, value TEXT NOT NULL)');
    }
    db.execute("INSERT INTO profiles(id,value) VALUES('p1','before')");
  } finally {
    db.close();
  }
}

void main() {
  late Directory dir;
  late String live;
  late String candidate;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('m4-d4b-retention-');
    live = '${dir.path}/live.sqlite';
    candidate = '${dir.path}/candidate.sqlite';
    _fixture(live);
    _fixture(candidate);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<RestoreReadOnlyPreviewEvidence> evidence() =>
      RestoreReadOnlyPreviewEvidence.captureReadOnly(
        liveDatabasePath: live,
        validatedCandidatePath: candidate,
      );

  test('read-only recheck preserves files; close cleans candidate once', () async {
    var calls = 0;
    final session = ReadOnlyImportRetention(
      evidence: await evidence(),
      liveDatabasePath: live,
      validatedCandidatePath: candidate,
      clearNative: (path) async {
        expect(path, candidate);
        calls++;
        File(path).deleteSync();
        return true;
      },
    );
    expect(session.evidence.liveCounts['profiles'], 1);
    expect(await session.recheckReadOnly(), RestorePreviewRecheck.unchanged);
    expect(File(candidate).existsSync(), isTrue);
    await session.close();
    await session.close();
    expect(session.cleaned, isTrue);
    expect(session.isClosed, isTrue);
    expect(calls, 1);
    expect(File(candidate).existsSync(), isFalse);
    expect(File(live).existsSync(), isTrue);
  });

  test('live data mismatch invalidates session and deletes quarantine', () async {
    final session = ReadOnlyImportRetention(
      evidence: await evidence(),
      liveDatabasePath: live,
      validatedCandidatePath: candidate,
      clearNative: (path) async {
        File(path).deleteSync();
        return true;
      },
    );
    final db = sqlite.sqlite3.open(live);
    db.execute("UPDATE profiles SET value='after' WHERE id='p1'");
    db.close();
    expect(await session.recheckReadOnly(),
        RestorePreviewRecheck.liveDataChanged);
    expect(session.isClosed, isTrue);
    expect(File(candidate).existsSync(), isFalse);
    expect(File(live).existsSync(), isTrue);
  });

  test('canceled session cannot be reused', () async {
    final session = ReadOnlyImportRetention(
      evidence: await evidence(),
      liveDatabasePath: live,
      validatedCandidatePath: candidate,
      clearNative: (_) async => true,
    );
    await session.close();
    expect(await session.recheckReadOnly(),
        RestorePreviewRecheck.invalidated);
  });

  test('failed cleanup is detectable and retryable without false success', () async {
    var attempts = 0;
    final session = ReadOnlyImportRetention(
      evidence: await evidence(),
      liveDatabasePath: live,
      validatedCandidatePath: candidate,
      clearNative: (_) async {
        attempts++;
        return attempts == 2;
      },
    );
    await expectLater(session.close(), throwsStateError);
    expect(session.cleaned, isFalse);
    await session.close();
    expect(session.cleaned, isTrue);
    expect(attempts, 2);
  });

  test('expiry invalidates and cleans the in-memory preview', () async {
    final expired = Completer<bool>();
    final session = ReadOnlyImportRetention(
      evidence: await evidence(),
      liveDatabasePath: live,
      validatedCandidatePath: candidate,
      maxRetention: const Duration(milliseconds: 20),
      clearNative: (path) async {
        File(path).deleteSync();
        return true;
      },
      onExpiry: expired.complete,
    );
    expect(await expired.future.timeout(const Duration(seconds: 2)), isTrue);
    expect(session.isClosed, isTrue);
    expect(session.cleaned, isTrue);
    expect(File(candidate).existsSync(), isFalse);
  });
}
