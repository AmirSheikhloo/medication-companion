import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';

void main() {
  test('v4 tasks and visits survive additive v5 care reminder migration', () async {
    final executor = NativeDatabase.memory(setup: (raw) {
      raw.execute('CREATE TABLE profiles (id TEXT NOT NULL PRIMARY KEY, '
          'display_name TEXT NOT NULL, kind TEXT NOT NULL, '
          'created_at INTEGER NOT NULL)');
      raw.execute('CREATE TABLE care_visits ('
          'id TEXT NOT NULL PRIMARY KEY, profile_id TEXT NOT NULL, '
          'title TEXT NOT NULL, doctor TEXT, location TEXT, purpose TEXT, '
          'scheduled_at INTEGER NOT NULL, status TEXT NOT NULL DEFAULT '
          "'scheduled', archived INTEGER NOT NULL DEFAULT 0, "
          'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)');
      raw.execute('CREATE TABLE care_tasks ('
          'id TEXT NOT NULL PRIMARY KEY, profile_id TEXT NOT NULL, '
          'visit_id TEXT, title TEXT NOT NULL, due_at INTEGER, '
          "status TEXT NOT NULL DEFAULT 'open', "
          'archived INTEGER NOT NULL DEFAULT 0, '
          'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)');
      raw.execute('CREATE TABLE care_task_events ('
          'id TEXT NOT NULL PRIMARY KEY, profile_id TEXT NOT NULL, '
          'task_id TEXT NOT NULL, action TEXT NOT NULL, recorded_at INTEGER NOT NULL)');
      raw.execute("INSERT INTO profiles VALUES ('p1','آزمایشی','self',100)");
      raw.execute("INSERT INTO care_visits VALUES ('v1','p1','ویزیت سابق',"
          "NULL,NULL,NULL,2000000000,'scheduled',0,100,100)");
      raw.execute("INSERT INTO care_tasks VALUES ('t1','p1','v1',"
          "'کار سابق',2000000000,'open',0,100,100)");
      raw.execute("INSERT INTO care_task_events VALUES ('e1','p1','t1','created',100)");
      raw.execute('PRAGMA user_version = 4');
    });
    final db = AppDatabase.forTesting(executor);
    try {
      final visits = await db.select(db.careVisits).get();
      final tasks = await db.select(db.careTasks).get();
      final events = await db.select(db.careTaskEvents).get();
      expect(visits.single.title, 'ویزیت سابق');
      expect(visits.single.reminderMinutesBefore, isNull);
      expect(visits.single.showChecklistDayBefore, isFalse);
      expect(visits.single.medicationId, isNull);
      expect(tasks.single.title, 'کار سابق');
      expect(tasks.single.reminderMinutesBefore, isNull);
      expect(tasks.single.repeatRule, 'none');
      expect(tasks.single.repeatAnchorDay, isNull);
      expect(events.single.action, 'created');
      expect(events.single.scheduledFor, isNull);
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 5);
    } finally {
      await db.close();
    }
  });
}
