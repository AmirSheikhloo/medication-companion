import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Safe diagnostic code with no patient data or private filesystem paths.
final class SnapshotSqliteFailure implements Exception {
  const SnapshotSqliteFailure(this.sqliteCode);

  final int sqliteCode;
}

/// Creates one transactionally consistent SQLite snapshot from the *trusted*
/// live Drift database, in a separate isolate and connection. We use exactly
/// the SQLite FFI engine already used by Drift, not Android's SQLiteDatabase
/// SQL wrapper. The source is opened READONLY, and VACUUM INTO has a bound
/// destination argument. The destination must already be an app-private path.
Future<void> createReadOnlySnapshot(String livePath, String snapshotPath) =>
    Isolate.run(() {
      final source = File(livePath);
      final target = File(snapshotPath);
      if (!source.isAbsolute || !target.isAbsolute ||
          !source.existsSync() || target.existsSync() ||
          !target.parent.existsSync() ||
          FileSystemEntity.isLinkSync(livePath) ||
          FileSystemEntity.isLinkSync(target.parent.path)) {
        throw const FileSystemException('Untrusted snapshot path');
      }

      final db = sqlite.sqlite3.open(livePath, mode: sqlite.OpenMode.readOnly);
      try {
        db.execute('PRAGMA busy_timeout=5000');
        db.execute('VACUUM INTO ?', [snapshotPath]);
        if (!target.existsSync() || target.lengthSync() < 4096) {
          throw const FileSystemException('Snapshot did not materialize');
        }
      } on sqlite.SqliteException catch (error) {
        if (target.existsSync()) target.deleteSync();
        throw SnapshotSqliteFailure(error.extendedResultCode);
      } catch (_) {
        if (target.existsSync()) target.deleteSync();
        rethrow;
      } finally {
        db.close();
      }
    });
