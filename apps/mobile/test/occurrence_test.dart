import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/features/medications/domain/occurrence.dart';

void main() {
  test('daily occurrence identity survives clock differences within a day', () {
    const plan = 'version-A';
    expect(
      OccurrenceKey.forDailyPlan(plan, DateTime(2026, 11, 16, 7)),
      OccurrenceKey.forDailyPlan(plan, DateTime(2026, 11, 16, 23, 59)),
    );
    expect(
      OccurrenceKey.forDailyPlan(plan, DateTime(2026, 11, 16)),
      isNot(OccurrenceKey.forDailyPlan(plan, DateTime(2026, 11, 17))),
    );
    expect(
      OccurrenceKey.forDailyPlan('version-B', DateTime(2026, 11, 16)),
      isNot(OccurrenceKey.forDailyPlan(plan, DateTime(2026, 11, 16))),
    );
  });
}
