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


/// A distinct physical package; balance is derived only from StockMovements.
/// Expiry is stored as a Gregorian ISO date with explicit precision.
class StockPackages extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get medicationId => text().references(Medications, #id)();
  TextColumn get label => text().withLength(min: 1, max: 80)();
  TextColumn get unit => text().withLength(min: 1, max: 30)();
  TextColumn get expiryIso => text().nullable()();
  TextColumn get expiryPrecision => text().withDefault(const Constant('none'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// At most one user-selected package for a medication.
class StockSelections extends Table {
  TextColumn get medicationId => text().references(Medications, #id)();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get packageId => text().references(StockPackages, #id)();

  @override
  Set<Column> get primaryKey => {medicationId};
}

/// Append-only, integer-thousandths accounting (no floating-point balance).
/// An undo references the exact previous debit and can reverse it only once.
class StockMovements extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get medicationId => text().references(Medications, #id)();
  TextColumn get packageId => text().references(StockPackages, #id)();
  TextColumn get kind => text()(); // initial | adjustment | taken | undo
  IntColumn get deltaMilliunits => integer()();
  TextColumn get occurrenceKey => text().nullable()();
  TextColumn get reversesMovementId =>
      text().nullable().references(StockMovements, #id)();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [{reversesMovementId}];
}

/// Null rule = no low-stock alert. Threshold applies to the selected package,
/// not an unsafe sum of different units/packages.
class StockAlertRules extends Table {
  TextColumn get medicationId => text().references(Medications, #id)();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get unit => text().withLength(min: 1, max: 30)();
  IntColumn get thresholdMilliunits => integer()();

  @override
  Set<Column> get primaryKey => {medicationId};
}

@DriftDatabase(tables: [
  Profiles,
  AppSettings,
  Medications,
  MedicationPlanVersions,
  DoseEvents,
  DoseCurrentStates,
  StockPackages,
  StockSelections,
  StockMovements,
  StockAlertRules,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'medication_companion_m1'));
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async => migrator.createAll(),
        onUpgrade: (migrator, from, to) async {
          if (from == 1 && to == 2) {
            // Additive migration: do not drop/rename existing personal data.
            // A transaction prevents partial schema upgrades if interrupted.
            await transaction(() async {
              await migrator.createTable(stockPackages);
              await migrator.createTable(stockSelections);
              await migrator.createTable(stockMovements);
              await migrator.createTable(stockAlertRules);
            });
            return;
          }
          throw StateError('Missing approved database migration $from -> $to');
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
