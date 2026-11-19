import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'database_lifecycle_lease.dart';

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

/// Current snapshot of a measurement; corrections keep a full version history.
class HealthMeasurements extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get metric => text()(); // pressure | glucose | weight | pulse
  IntColumn get primaryMilliunits => integer()();
  IntColumn get secondaryMilliunits => integer().nullable()();
  TextColumn get unit => text()();
  TextColumn get context => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get observedAt => dateTime()();
  DateTimeColumn get recordedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Immutable snapshots: every creation, correction, or archive is recorded.
class HealthMeasurementVersions extends Table {
  TextColumn get id => text()();
  TextColumn get measurementId => text().references(HealthMeasurements, #id)();
  TextColumn get profileId => text().references(Profiles, #id)();
  IntColumn get version => integer()();
  TextColumn get action => text()(); // created | corrected | archived
  TextColumn get metric => text()();
  IntColumn get primaryMilliunits => integer()();
  IntColumn get secondaryMilliunits => integer().nullable()();
  TextColumn get unit => text()();
  TextColumn get context => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get observedAt => dateTime()();
  DateTimeColumn get changedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [{measurementId, version}];
}


/* M3-03A: local care planning. Never cascade-delete a user's records. */
class CareVisits extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get title => text().withLength(min: 1, max: 160)();
  TextColumn get doctor => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get purpose => text().nullable()();
  DateTimeColumn get scheduledAt => dateTime()();
  IntColumn get reminderMinutesBefore => integer().nullable()();
  BoolColumn get showChecklistDayBefore => boolean().withDefault(const Constant(false))();
  TextColumn get medicationId => text().nullable().references(Medications, #id)();
  TextColumn get status => text().withDefault(const Constant('scheduled'))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class CareTasks extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get visitId => text().nullable().references(CareVisits, #id)();
  TextColumn get title => text().withLength(min: 1, max: 160)();
  DateTimeColumn get dueAt => dateTime().nullable()();
  IntColumn get reminderMinutesBefore => integer().nullable()();
  TextColumn get repeatRule => text().withDefault(const Constant('none'))();
  IntColumn get repeatAnchorDay => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Append-only record of task state changes; profile scoped.
class CareTaskEvents extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get taskId => text().references(CareTasks, #id)();
  TextColumn get action => text()(); // includes completed_cycle for repeating tasks
  DateTimeColumn get scheduledFor => dateTime().nullable()();
  DateTimeColumn get recordedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class VisitChecklistItems extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get visitId => text().references(CareVisits, #id)();
  TextColumn get phase => text()(); // before | after
  TextColumn get title => text().withLength(min: 1, max: 160)();
  IntColumn get position => integer()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get checked => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

class VisitQuestions extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get visitId => text().nullable().references(CareVisits, #id)();
  TextColumn get question => text().withLength(min: 1, max: 500)();
  BoolColumn get answered => boolean().withDefault(const Constant(false))();
  DateTimeColumn get answeredAt => dateTime().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
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
  HealthMeasurements,
  HealthMeasurementVersions,
  CareVisits,
  CareTasks,
  CareTaskEvents,
  VisitChecklistItems,
  VisitQuestions,
])
class AppDatabase extends _$AppDatabase {
  final DatabaseLifecycleLease? _lease;

  AppDatabase._guarded(this._lease)
      : super(driftDatabase(name: 'medication_companion_m1'));
  AppDatabase.forTesting(super.executor) : _lease = null;

  /// No production constructor may create or open a database before acquiring
  /// a lifetime-held native lock. A headless engine lacking the MethodChannel
  /// must fail without constructing Drift, rather than silently bypassing it.
  static Future<AppDatabase> openGuarded() async {
    final lease = await DatabaseLifecycleLease.acquire();
    try {
      return AppDatabase._guarded(lease);
    } catch (_) {
      await lease.release();
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    try {
      // Await every Drift executor shutdown before releasing the native lease.
      await super.close();
    } finally {
      final lease = _lease;
      if (lease != null) await lease.release();
    }
  }

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async => migrator.createAll(),
        onUpgrade: (migrator, from, to) async {
          // All upgrade paths are additive. Users can jump directly from
          // v1 to v5 without installing every intermediate build.
          if (to != 5 || from < 1 || from > 4) {
            throw StateError('Missing approved database migration $from -> $to');
          }
          await transaction(() async {
            if (from == 1) {
              await migrator.createTable(stockPackages);
              await migrator.createTable(stockSelections);
              await migrator.createTable(stockMovements);
              await migrator.createTable(stockAlertRules);
            }
            if (from <= 2) {
              await migrator.createTable(healthMeasurements);
              await migrator.createTable(healthMeasurementVersions);
            }
            if (from <= 3) {
              await migrator.createTable(careVisits);
              await migrator.createTable(careTasks);
              await migrator.createTable(careTaskEvents);
              await migrator.createTable(visitChecklistItems);
              await migrator.createTable(visitQuestions);
            } else {
              await migrator.addColumn(careVisits, careVisits.reminderMinutesBefore);
              await migrator.addColumn(careVisits, careVisits.showChecklistDayBefore);
              await migrator.addColumn(careVisits, careVisits.medicationId);
              await migrator.addColumn(careTasks, careTasks.reminderMinutesBefore);
              await migrator.addColumn(careTasks, careTasks.repeatRule);
              await migrator.addColumn(careTasks, careTasks.repeatAnchorDay);
              await migrator.addColumn(careTaskEvents, careTaskEvents.scheduledFor);
            }
          });
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
