import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/health/data/health_repository.dart';
import 'package:medication_companion/features/health/domain/health_metric.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  late AppDatabase db;
  late HealthRepository health;
  late ProfileRepository profiles;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    health = HealthRepository(db);
    profiles = ProfileRepository(db);
  });
  tearDown(() async => db.close());

  HealthMeasurementDraft value({
    HealthMetric metric = HealthMetric.pressure,
    int first = 120000,
    int? second = 80000,
    DateTime? at,
    String? context,
    String? note,
  }) =>
      HealthMeasurementDraft(
        metric: metric,
        primaryMilliunits: first,
        secondaryMilliunits: second,
        observedAt: at ?? DateTime.now(),
        context: context,
        note: note,
      );

  test('Persian/Arabic decimal input is exact and invalid entries reject', () {
    expect(HealthNumber.parseMilliunits('۱۲٫۵'), 12500);
    expect(HealthNumber.parseMilliunits('١٢.٥٠'), 12500);
    expect(HealthNumber.parseMilliunits('0.001'), 1);
    expect(HealthNumber.format(12500), '12.5');
    expect(HealthNumber.format(120000), '120');
    expect(() => HealthNumber.parseMilliunits('-1'), throwsFormatException);
    expect(() => HealthNumber.parseMilliunits('1.2345'), throwsFormatException);
    expect(() => HealthNumber.parseMilliunits('0'), throwsFormatException);
    expect(() => HealthNumber.parseMilliunits('1,200'), throwsFormatException);
  });

  test('insert, correction and archive retain immutable versions', () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    final id = await health.addMeasurement(
      profileId: profile.id,
      draft: value(note: 'ثبت اولیه'),
    );
    final initial = await health.measurementsFor(profileId: profile.id);
    expect(initial, hasLength(1));
    expect(initial.single.primaryMilliunits, 120000);
    expect(initial.single.secondaryMilliunits, 80000);
    expect(initial.single.unit, 'mmHg');
    expect(initial.single.version, 1);

    await health.correctMeasurement(
      profileId: profile.id,
      measurementId: id,
      draft: value(first: 124500, second: 82000, note: 'اصلاح دستی'),
    );
    var entries = await health.measurementsFor(profileId: profile.id);
    expect(entries.single.primaryMilliunits, 124500);
    expect(entries.single.version, 2);
    var history = await health.versionsFor(
      profileId: profile.id, measurementId: id);
    expect(history.map((v) => v.action), ['created', 'corrected']);
    expect(history.map((v) => v.primaryMilliunits), [120000, 124500]);

    await health.archiveMeasurement(
      profileId: profile.id, measurementId: id);
    entries = await health.measurementsFor(profileId: profile.id);
    expect(entries, isEmpty);
    history = await health.versionsFor(
      profileId: profile.id, measurementId: id);
    expect(history.map((v) => v.action),
        ['created', 'corrected', 'archived']);
    expect(history.last.primaryMilliunits, 124500);
    expect(history.last.version, 3);
    expect(await db.select(db.healthMeasurements).get(), hasLength(1));
    await expectLater(
      health.archiveMeasurement(profileId: profile.id, measurementId: id),
      throwsStateError,
    );
  });

  test('cross-profile reads, corrections and archives are rejected', () async {
    final mine = await profiles.createGuestProfile(forSelf: true);
    final other = await profiles.createGuestProfile(forSelf: false);
    final id = await health.addMeasurement(
      profileId: mine.id, draft: value());
    expect(await health.measurementsFor(profileId: other.id), isEmpty);
    await expectLater(
      health.correctMeasurement(
        profileId: other.id, measurementId: id,
        draft: value(first: 100000)),
      throwsStateError,
    );
    await expectLater(
      health.archiveMeasurement(
        profileId: other.id, measurementId: id),
      throwsStateError,
    );
    await expectLater(
      health.versionsFor(profileId: other.id, measurementId: id),
      throwsStateError,
    );
    expect((await health.measurementsFor(profileId: mine.id)).single.version, 1);
    expect(await db.select(db.healthMeasurementVersions).get(), hasLength(1));
  });

  test('invalid input cannot partially write and type cannot change', () async {
    final p = await profiles.createGuestProfile(forSelf: true);
    await expectLater(
      health.addMeasurement(
        profileId: p.id,
        draft: value(second: null)),
      throwsArgumentError,
    );
    await expectLater(
      health.addMeasurement(
        profileId: p.id,
        draft: value(
          metric: HealthMetric.glucose,
          first: 100000,
          second: null,
          context: null,
        )),
      throwsArgumentError,
    );
    await expectLater(
      health.addMeasurement(
        profileId: p.id,
        draft: value(at: DateTime.now().add(const Duration(days: 1)))),
      throwsArgumentError,
    );
    expect(await db.select(db.healthMeasurements).get(), isEmpty);
    expect(await db.select(db.healthMeasurementVersions).get(), isEmpty);
    final id = await health.addMeasurement(
      profileId: p.id, draft: value());
    await expectLater(
      health.correctMeasurement(
        profileId: p.id, measurementId: id,
        draft: value(
          metric: HealthMetric.weight,
          first: 76500,
          second: null,
        )),
      throwsArgumentError,
    );
    expect((await health.measurementsFor(profileId: p.id)).single.version, 1);
  });

  test('metric and date filters are profile-scoped and show no fake data',
      () async {
    final p = await profiles.createGuestProfile(forSelf: true);
    await health.addMeasurement(
      profileId: p.id,
      draft: value(
        metric: HealthMetric.glucose,
        first: 94500,
        second: null,
        context: 'fasting',
        at: DateTime.now().subtract(const Duration(days: 2)),
      ),
    );
    await health.addMeasurement(
      profileId: p.id,
      draft: value(
        metric: HealthMetric.weight,
        first: 73400,
        second: null,
        at: DateTime.now().subtract(const Duration(days: 50)),
      ),
    );
    expect(
      await health.measurementsFor(
        profileId: p.id, metric: HealthMetric.glucose, days: 7),
      hasLength(1),
    );
    expect(
      await health.measurementsFor(
        profileId: p.id, metric: HealthMetric.weight, days: 30),
      isEmpty,
    );
    expect(
      await health.measurementsFor(profileId: p.id, days: 90),
      hasLength(2),
    );
  });
}
