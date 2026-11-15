import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Every health-related row belongs to a profile. Never query across profiles
/// from the presentation layer without an explicit active-profile filter.
class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text().withLength(min: 1, max: 80)();
  TextColumn get kind => text()(); // self | managed
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class Medications extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get name => text().withLength(min: 1, max: 160)();
  TextColumn get unit => text().withDefault(const Constant('عدد'))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Immutable for M1: a schedule edit will append another plan version.
class MedicationPlanVersions extends Table {
  TextColumn get id => text()();
  TextColumn get medicationId => text().references(Medications, #id)();
  IntColumn get version => integer()();
  TextColumn get doseText => text().withLength(min: 1, max: 120)();
  IntColumn get hour => integer()();
  IntColumn get minute => integer()();
  DateTimeColumn get effectiveFrom => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Append-only account of what the user/caregiver reported.
class DoseEvents extends Table {
  TextColumn get id => text()();
  TextColumn get occurrenceKey => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get medicationId => text().references(Medications, #id)();
  TextColumn get action => text()(); // taken | skipped | unknown | undo
  DateTimeColumn get recordedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One effective state per occurrence, atomically updated with DoseEvents.
class DoseCurrentStates extends Table {
  TextColumn get occurrenceKey => text()();
  TextColumn get status => text()(); // pending | taken | skipped | unknown
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {occurrenceKey};
}

@DriftDatabase(tables: [
  Profiles,
  AppSettings,
  Medications,
  MedicationPlanVersions,
  DoseEvents,
  DoseCurrentStates,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'medication_companion_m1'));
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async => migrator.createAll(),
        onUpgrade: (migrator, from, to) async {
          // Future versions must use explicit, tested migrations. Do not
          // silently delete health data or drop/recreate existing tables.
          throw StateError('Missing approved database migration $from -> $to');
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
