import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/inventory/data/inventory_repository.dart';

void main() {
  test('v1 SQLite health records survive additive v2 stock migration', () async {
    // Create a version-1 file in memory BEFORE opening AppDatabase v2.
    // This mimics an existing user's M1/M2 database with recorded doses.
    final executor = NativeDatabase.memory();
    await executor.runCustom(
      'CREATE TABLE profiles ('
      'id TEXT NOT NULL PRIMARY KEY, '
      'display_name TEXT NOT NULL, kind TEXT NOT NULL, created_at INTEGER NOT NULL)',
    );
    await executor.runCustom(
      'CREATE TABLE app_settings (key TEXT NOT NULL PRIMARY KEY, '
      'value TEXT NOT NULL)',
    );
    await executor.runCustom(
      'CREATE TABLE medications ('
      'id TEXT NOT NULL PRIMARY KEY, profile_id TEXT NOT NULL '
      'REFERENCES profiles(id), name TEXT NOT NULL, '
      "unit TEXT NOT NULL DEFAULT 'عدد', archived INTEGER NOT NULL DEFAULT 0, "
      'created_at INTEGER NOT NULL)',
    );
    await executor.runCustom(
      'CREATE TABLE medication_plan_versions ('
      'id TEXT NOT NULL PRIMARY KEY, medication_id TEXT NOT NULL '
      'REFERENCES medications(id), version INTEGER NOT NULL, '
      'dose_text TEXT NOT NULL, hour INTEGER NOT NULL, minute INTEGER NOT NULL, '
      'effective_from INTEGER NOT NULL)',
    );
    await executor.runCustom(
      'CREATE TABLE dose_events ('
      'id TEXT NOT NULL PRIMARY KEY, occurrence_key TEXT NOT NULL, '
      'profile_id TEXT NOT NULL REFERENCES profiles(id), '
      'medication_id TEXT NOT NULL REFERENCES medications(id), '
      'action TEXT NOT NULL, recorded_at INTEGER NOT NULL)',
    );
    await executor.runCustom(
      'CREATE TABLE dose_current_states ('
      'occurrence_key TEXT NOT NULL PRIMARY KEY, '
      'status TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    );
    await executor.runCustom(
      "INSERT INTO profiles VALUES ('p1', 'نمونه', 'self', 100)",
    );
    await executor.runCustom(
      "INSERT INTO medications VALUES ('m1', 'p1', 'داروی قبلی', 'عدد', 0, 101)",
    );
    await executor.runCustom(
      "INSERT INTO medication_plan_versions VALUES "
      "('plan1', 'm1', 1, 'طبق نسخه', 8, 0, 101)",
    );
    await executor.runCustom(
      "INSERT INTO dose_events VALUES ('ev1', 'occ1', 'p1', 'm1', 'taken', 102)",
    );
    await executor.runCustom(
      "INSERT INTO dose_current_states VALUES ('occ1', 'taken', 102)",
    );
    await executor.runCustom('PRAGMA user_version = 1');

    final db = AppDatabase.forTesting(executor);
    try {
      final meds = await db.select(db.medications).get();
      expect(meds, hasLength(1));
      expect(meds.single.name, 'داروی قبلی');
      expect((await db.select(db.profiles).get()).single.displayName, 'نمونه');
      expect((await db.select(db.doseEvents).get()).single.action, 'taken');
      expect((await db.select(db.doseCurrentStates).get()).single.status, 'taken');
      expect((await db.select(db.medicationPlanVersions).get()), hasLength(1));
      final stock = InventoryRepository(db);
      expect((await stock.summary('p1', 'm1')).packages, isEmpty);
      final packageId = await stock.addPackage(
        profileId: 'p1', medicationId: 'm1',
        label: 'پس از ارتقا', unit: 'عدد',
        initialMilliunits: 3000, selectForUse: true,
      );
      expect((await stock.summary('p1', 'm1')).selectedPackageId, packageId);
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 2);
    } finally {
      await db.close();
    }
  });
}
