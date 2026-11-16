import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/health/data/health_report_export.dart';
import 'package:medication_companion/features/health/data/health_repository.dart';
import 'package:medication_companion/features/health/domain/health_metric.dart';
import 'package:medication_companion/features/health/domain/health_report.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late Profile profile;
  late HealthRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    profile = await ProfileRepository(db).createGuestProfile(forSelf: true);
    repo = HealthRepository(db);
  });
  tearDown(() async => db.close());

  Future<HealthMeasurement> record({
    HealthMetric metric = HealthMetric.pressure,
    int primary = 120000,
    int? secondary = 80000,
    String? context,
    String? note,
    DateTime? observed,
  }) async {
    final id = await repo.addMeasurement(
      profileId: profile.id,
      draft: HealthMeasurementDraft(
        metric: metric,
        primaryMilliunits: primary,
        secondaryMilliunits: secondary,
        observedAt: observed ?? DateTime.now(),
        context: context,
        note: note,
      ),
    );
    return (db.select(db.healthMeasurements)
          ..where((t) => t.id.equals(id)))
        .getSingle();
  }

  test('pressure summary separates top/bottom and computes descriptive means',
      () async {
    final a = await record();
    final b = await record(primary: 128000, secondary: 84000);
    final summary = HealthReportSummary.calculate(
      HealthMetric.pressure, [a, b]);
    expect(summary.count, 2);
    expect(summary.stats['فشار بالا']?.meanMilliunits, 124000);
    expect(summary.stats['فشار پایین']?.meanMilliunits, 82000);
    expect(summary.stats['فشار بالا']?.minMilliunits, 120000);
    expect(summary.stats['فشار بالا']?.maxMilliunits, 128000);
    expect(summary.excludedCount, 0);
    expect(HealthReportSummary.calculate(HealthMetric.pulse, []).stats, isEmpty);
  });

  test('glucose summary never blends fasting with after-meal data', () async {
    final first = await record(
      metric: HealthMetric.glucose,
      primary: 90000,
      secondary: null,
      context: 'fasting',
    );
    final second = await record(
      metric: HealthMetric.glucose,
      primary: 160000,
      secondary: null,
      context: 'after_meal',
    );
    final summary = HealthReportSummary.calculate(
      HealthMetric.glucose, [first, second]);
    expect(summary.stats.keys.toSet(), {'ناشتا', 'بعد غذا'});
    expect(summary.stats['ناشتا']?.meanMilliunits, 90000);
    expect(summary.stats['بعد غذا']?.meanMilliunits, 160000);
    expect(summary.stats.values.map((s) => s.count), [1, 1]);
  });

  test('local inclusive calendar date range excludes out-of-range records',
      () async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1, 9);
    final old = DateTime(now.year, now.month, now.day - 10, 9);
    final recent = await record(observed: yesterday);
    final previous = await record(observed: old);
    final selected = selectHealthDateRange(
      records: [previous, recent],
      startLocal: DateTime(now.year, now.month, now.day - 2),
      endLocal: DateTime(now.year, now.month, now.day),
    );
    expect(selected.map((r) => r.id), [recent.id]);
    expect(
      () => selectHealthDateRange(
        records: [],
        startLocal: DateTime(2026, 11, 16),
        endLocal: DateTime(2026, 11, 15),
      ),
      throwsArgumentError,
    );
  });

  test('CSV has UTF-8 BOM, Persian headers, escaped user text and no other profiles',
      () async {
    final unsafe = await record(
      metric: HealthMetric.weight,
      primary: 73500,
      secondary: null,
      note: '=SUM(1,1) "bad"',
    );
    final another = await ProfileRepository(db)
        .createGuestProfile(forSelf: false, displayName: 'داده دیگری');
    final date = DateTime.now();
    final csv = buildHealthCsv(
      profile: profile,
      metric: HealthMetric.weight,
      start: date,
      end: date,
      records: [unsafe],
    );
    expect(utf8.encode(csv).take(3).toList(), [0xEF, 0xBB, 0xBF]);
    expect(csv, contains('پروفایل'));
    expect(csv, contains('73.5'));
    expect(csv, contains("'=SUM(1,1)"));
    expect(csv, contains('""bad""'));
    expect(csv, contains('تأیید پزشکی نشده'));
    expect(csv, isNot(contains(another.displayName)));
    final emptyCsv = buildHealthCsv(
      profile: profile,
      metric: HealthMetric.weight,
      start: date,
      end: date,
      records: [],
    );
    expect(emptyCsv, contains('داده‌ای ثبت نشده است'));
  });

  test('offline Persian PDF generation returns a valid PDF file', () async {
    final item = await record(note: 'فقط تست ساختگی');
    final now = DateTime.now();
    final bytes = await const HealthReportExport().buildPdf(
      profile: profile,
      metric: HealthMetric.pressure,
      start: now,
      end: now,
      records: [item],
    );
    expect(bytes.length, greaterThan(500));
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
  });
}
