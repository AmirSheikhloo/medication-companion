import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Only the 17 SQLite tables shipped by the live v5 Drift database.
const backedUpTables = <String>[
  'profiles',
  'app_settings',
  'medications',
  'medication_plan_versions',
  'dose_events',
  'dose_current_states',
  'stock_packages',
  'stock_selections',
  'stock_movements',
  'stock_alert_rules',
  'health_measurements',
  'health_measurement_versions',
  'care_visits',
  'care_tasks',
  'care_task_events',
  'visit_checklist_items',
  'visit_questions',
];

/// Dart FFI native asset MUST be the same libsqlite3 instance holding the
/// Database.handle returned by package:sqlite3. No system libsqlite3 dlopen.
typedef _Authorization = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Int32,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
);

@ffi.Native<
  ffi.Int32 Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.NativeFunction<_Authorization>>,
    ffi.Pointer<ffi.Void>,
  )
>(symbol: 'sqlite3_set_authorizer', assetId: 'package:sqlite3/src/ffi/libsqlite3.g.dart')
external int _sqliteSetAuthorizer(
  ffi.Pointer<ffi.Void> db,
  ffi.Pointer<ffi.NativeFunction<_Authorization>> callback,
  ffi.Pointer<ffi.Void> userData,
);

// https://www.sqlite.org/c3ref/c_alter_table.html authorizer callback codes.
const _sqlitePragma = 19;
const _sqliteRead = 20;
const _sqliteSelect = 21;
const _sqliteFunction = 31;
const _sqliteOk = 0;
const _sqliteDeny = 1;

const _allowedPragmas = <String>{
  'integrity_check', 'foreign_key_check', 'user_version',
  'page_size', 'page_count', 'table_info', 'index_list',
  'index_info', 'foreign_key_list',
};

const _allowedFunctions = <String>{
  'count', 'sum', 'min', 'max', 'length', 'typeof', 'glob', 'like',
  'hex', 'quote', 'coalesce', 'ifnull', 'substr', 'lower', 'upper',
  'printf', 'format', 'nullif', 'abs',
};

final _readableTables = <String>{
  ...backedUpTables,
  'sqlite_master', 'sqlite_schema', 'sqlite_sequence',
};

String _nativeString(ffi.Pointer<Utf8> p) =>
    p == ffi.nullptr ? '' : p.toDartString();

/// SQLite invokes this synchronously on the inspecting isolate only.
int _authorize(
  ffi.Pointer<ffi.Void> _,
  int operation,
  ffi.Pointer<Utf8> first,
  ffi.Pointer<Utf8> second,
  ffi.Pointer<Utf8> third,
  ffi.Pointer<Utf8> fourth,
) {
  try {
    switch (operation) {
      case _sqliteSelect:
        return _sqliteOk;
      case _sqliteRead:
        return _readableTables.contains(_nativeString(first).toLowerCase())
            ? _sqliteOk
            : _sqliteDeny;
      case _sqlitePragma:
        return _allowedPragmas.contains(_nativeString(first).toLowerCase())
            ? _sqliteOk
            : _sqliteDeny;
      case _sqliteFunction:
        return _allowedFunctions.contains(_nativeString(second).toLowerCase())
            ? _sqliteOk
            : _sqliteDeny;
      default:
        // ATTACH/DETACH, DDL, UPDATE, INSERT, DELETE, triggers, transactions,
        // savepoints, recursive statements and all unknown operations.
        return _sqliteDeny;
    }
  } catch (_) {
    return _sqliteDeny;
  }
}

/// A schema template read from the currently installed, trusted v5 app DB.
/// The original SQL text is compared exactly after whitespace normalization.
/// Incompatible legacy migrations are rejected rather than guessed.
typedef BackupSchema = List<String>;

String _schemaEntry(String type, String name, String table, String? sql) =>
    '$type\u0000$name\u0000$table\u0000${(sql ?? '').replaceAll(RegExp(r'\s+'), ' ').trim()}';

BackupSchema schemaTemplate(Iterable<Map<String, Object?>> rows) {
  final entries = <String>[];
  final tableNames = <String>{};
  for (final row in rows) {
    final type = row['type'] as String;
    final name = row['name'] as String;
    final table = row['tbl_name'] as String;
    final sql = row['sql'] as String?;
    if (type != 'table' && type != 'index') {
      throw const FormatException('Unexpected live schema object');
    }
    if (type == 'table') tableNames.add(name);
    entries.add(_schemaEntry(type, name, table, sql));
  }
  if (tableNames.difference({...backedUpTables, 'sqlite_sequence'}).isNotEmpty ||
      !tableNames.containsAll(backedUpTables)) {
    throw const FormatException('Live v5 schema baseline is not supported');
  }
  entries.sort();
  return entries;
}

/// Returns authenticated, strictly inspected row counts; never exposes data or
/// writes to the candidate database. Runs outside the Flutter UI isolate.
Future<Map<String, int>> inspectAuthenticatedBackup(
  String quarantinedPath,
  BackupSchema trustedLiveSchema,
) => Isolate.run(() => _inspect(quarantinedPath, trustedLiveSchema));

Map<String, int> _inspect(String path, BackupSchema expectedSchema) {
  final candidate = File(path);
  if (FileSystemEntity.isLinkSync(path) ||
      !candidate.isAbsolute ||
      !candidate.existsSync() ||
      candidate.lengthSync() < 4096 ||
      candidate.lengthSync() > 64 * 1024 * 1024) {
    throw const FormatException('Quarantined file is invalid');
  }
  // Read the fixed header without involving SQLite first. A MCBK export uses
  // rollback-journal format; rejecting WAL-mode headers prevents sqlite3 from
  // generating -wal/-shm companion files during the preview.
  final source = candidate.openSync(mode: FileMode.read);
  late final List<int> header;
  try {
    header = source.readSync(100);
  } finally {
    source.closeSync();
  }
  const magic = <int>[83, 81, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0];
  if (header.length != 100 ||
      !List.generate(magic.length, (i) => i).every((i) => header[i] == magic[i]) ||
      header[18] != 1 || header[19] != 1) {
    throw const FormatException('Invalid or WAL-mode SQLite image');
  }
  // sqlite3.open(readOnly) is not allowed to create or change the file.
  final db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
  final callback = ffi.NativeCallable<_Authorization>.isolateLocal(_authorize);
  try {
    // All config operations MUST succeed, otherwise stop before SQL executes.
    // sqlite3_db_config constants from sqlite3.h.
    db.config.setIntConfig(1017, 0); // TRUSTED_SCHEMA off
    db.config.setIntConfig(1010, 1); // DEFENSIVE on
    db.config.setIntConfig(1005, 0); // ENABLE_LOAD_EXTENSION off
    db.config.setIntConfig(1003, 0); // ENABLE_TRIGGER off
    db.config.setIntConfig(1015, 0); // ENABLE_VIEW off
    db.execute('PRAGMA mmap_size=0');
    db.execute('PRAGMA cell_size_check=ON');
    db.execute('PRAGMA writable_schema=OFF');
    if (_sqliteSetAuthorizer(db.handle, callback.nativeFunction, ffi.nullptr) != 0) {
      throw const FormatException('SQLite authorizer unavailable');
    }

    // Discover structure before any user-table SELECT or integrity scanner.
    final structure = db.select(
      'SELECT type, name, tbl_name, sql FROM sqlite_master '
      'ORDER BY type, name',
    );
    final actual = schemaTemplate(structure.map((row) => {
      'type': row['type'], 'name': row['name'],
      'tbl_name': row['tbl_name'], 'sql': row['sql'],
    }));
    if (actual.length != expectedSchema.length ||
        !actual.asMap().entries.every((entry) =>
            entry.value == expectedSchema[entry.key])) {
      throw const FormatException('Backup schema is not an exact v5 match');
    }
    final version = db.select('PRAGMA user_version').single.values.single;
    if (version != 5) throw const FormatException('Unsupported database version');
    final pageSize = db.select('PRAGMA page_size').single.values.single as int;
    final pageCount = db.select('PRAGMA page_count').single.values.single as int;
    final size = candidate.lengthSync();
    if (pageSize < 512 || pageSize > 65536 ||
        (pageSize & (pageSize - 1)) != 0 ||
        pageCount < 1 || pageCount > size ~/ pageSize ||
        pageSize * pageCount > size) {
      throw const FormatException('Invalid SQLite page dimensions');
    }
    final integrity = db.select('PRAGMA integrity_check(10)');
    if (integrity.length != 1 || integrity.single.values.single != 'ok') {
      throw const FormatException('SQLite integrity check failed');
    }
    if (db.select('PRAGMA foreign_key_check').isNotEmpty) {
      throw const FormatException('SQLite foreign keys are inconsistent');
    }
    final counts = <String, int>{};
    for (final table in backedUpTables) {
      final count = db.select('SELECT COUNT(*) AS n FROM "$table"').single['n'];
      if (count is! int || count < 0) {
        throw const FormatException('Invalid backup row count');
      }
      counts[table] = count;
    }
    return counts;
  } finally {
    db.close();
    callback.close();
  }
}
