import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/health/data/health_repository.dart';
import 'package:medication_companion/features/health/domain/health_metric.dart';

void main() {
  test('v2 stock and medication history survive v5 upgrade', () async {
    final executor = NativeDatabase.memory(setup: (raw) {
      // Actual v2 table/column names; do not reset the user's offline file.
      raw.execute('CREATE TABLE profiles ('
          'id TEXT NOT NULL PRIMARY KEY, display_name TEXT NOT NULL, '
          'kind TEXT NOT NULL, created_at INTEGER NOT NULL)');
      raw.execute('CREATE TABLE app_settings ('
          'key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)');
      raw.execute('CREATE TABLE medications ('
          'id TEXT NOT NULL PRIMARY KEY, profile_id TEXT NOT NULL '
          'REFERENCES profiles(id), name TEXT NOT NULL, '
          "unit TEXT NOT NULL DEFAULT 'عدد', "
          'archived INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)');
      raw.execute('CREATE TABLE medication_plan_versions ('
          'id TEXT NOT NULL PRIMARY KEY, medication_id TEXT NOT NULL '
          'REFERENCES medications(id), version INTEGER NOT NULL, '
          'dose_text TEXT NOT NULL, hour INTEGER NOT NULL, '
          'minute INTEGER NOT NULL, effective_from INTEGER NOT NULL)');
      raw.execute('CREATE TABLE dose_events ('
          'id TEXT NOT NULL PRIMARY KEY, occurrence_key TEXT NOT NULL, '
          'profile_id TEXT NOT NULL REFERENCES profiles(id), '
          'medication_id TEXT NOT NULL REFERENCES medications(id), '
          'action TEXT NOT NULL, recorded_at INTEGER NOT NULL)');
      raw.execute('CREATE TABLE dose_current_states ('
          'occurrence_key TEXT NOT NULL PRIMARY KEY, '
          'status TEXT NOT NULL, updated_at INTEGER NOT NULL)');
      raw.execute('CREATE TABLE stock_packages ('
          'id TEXT NOT NULL PRIMARY KEY, '
          'profile_id TEXT NOT NULL REFERENCES profiles(id), '
          'medication_id TEXT NOT NULL REFERENCES medications(id), '
          'label TEXT NOT NULL, unit TEXT NOT NULL, '
          'expiry_iso TEXT NULL, '
          "expiry_precision TEXT NOT NULL DEFAULT 'none', "
          'created_at INTEGER NOT NULL)');
      raw.execute('CREATE TABLE stock_selections ('
          'medication_id TEXT NOT NULL PRIMARY KEY REFERENCES medications(id), '
          'profile_id TEXT NOT NULL REFERENCES profiles(id), '
          'package_id TEXT NOT NULL REFERENCES stock_packages(id))');
      raw.execute('CREATE TABLE stock_movements ('
          'id TEXT NOT NULL PRIMARY KEY, '
          'profile_id TEXT NOT NULL REFERENCES profiles(id), '
          'medication_id TEXT NOT NULL REFERENCES medications(id), '
          'package_id TEXT NOT NULL REFERENCES stock_packages(id), '
          'kind TEXT NOT NULL, delta_milliunits INTEGER NOT NULL, '
          'occurrence_key TEXT NULL, '
          'reverses_movement_id TEXT NULL UNIQUE REFERENCES stock_movements(id), '
          'note TEXT NULL, created_at INTEGER NOT NULL)');
      raw.execute('CREATE TABLE stock_alert_rules ('
          'medication_id TEXT NOT NULL PRIMARY KEY REFERENCES medications(id), '
          'profile_id TEXT NOT NULL REFERENCES profiles(id), '
          'unit TEXT NOT NULL, threshold_milliunits INTEGER NOT NULL)');

      raw.execute("INSERT INTO profiles VALUES ('p1','مادر','managed',100)");
      raw.execute("INSERT INTO medications VALUES ("
          "'m1','p1','داروی سابق','عدد',0,101)");
      raw.execute("INSERT INTO medication_plan_versions VALUES ("
          "'plan1','m1',1,'صبح',9,0,101)");
      raw.execute("INSERT INTO dose_events VALUES ("
          "'dose1','occ1','p1','m1','taken',102)");
      raw.execute("INSERT INTO stock_packages VALUES ("
          "'pack1','p1','m1','بسته قدیمی','عدد',NULL,'none',101)");
      raw.execute("INSERT INTO stock_selections VALUES ('m1','p1','pack1')");
      raw.execute("INSERT INTO stock_movements VALUES ("
          "'movement1','p1','m1','pack1','initial',4000,NULL,NULL,NULL,101)");
      raw.execute("INSERT INTO stock_alert_rules VALUES ('m1','p1','عدد',3000)");
      raw.execute('PRAGMA user_version = 2');
    });
    final db = AppDatabase.forTesting(executor);
    try {
      expect((await db.select(db.profiles).get()).single.displayName, 'مادر');
      expect((await db.select(db.medications).get()).single.name, 'داروی سابق');
      expect((await db.select(db.doseEvents).get()).single.action, 'taken');
      expect((await db.select(db.stockPackages).get()).single.id, 'pack1');
      expect((await db.select(db.stockMovements).get())
          .single.deltaMilliunits, 4000);
      expect((await db.select(db.stockSelections).get())
          .single.packageId, 'pack1');
      expect((await db.select(db.stockAlertRules).get())
          .single.thresholdMilliunits, 3000);
      final health = HealthRepository(db);
      await health.addMeasurement(
        profileId: 'p1',
        draft: HealthMeasurementDraft(
          metric: HealthMetric.pulse,
          primaryMilliunits: 72000,
          observedAt: DateTime.now(),
        ),
      );
      expect(await db.select(db.healthMeasurements).get(), hasLength(1));
      expect(await db.select(db.healthMeasurementVersions).get(), hasLength(1));
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 5);
    } finally {
      await db.close();
    }
  });
}
