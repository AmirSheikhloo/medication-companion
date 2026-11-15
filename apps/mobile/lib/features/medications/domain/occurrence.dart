/// A stable local identity for a daily dose, independent of notification IDs.
/// Plans are immutable versions: editing a schedule creates a new plan id.
class OccurrenceKey {
  const OccurrenceKey._();

  static String forDailyPlan(String planVersionId, DateTime localDay) {
    final year = localDay.year.toString().padLeft(4, '0');
    final month = localDay.month.toString().padLeft(2, '0');
    final day = localDay.day.toString().padLeft(2, '0');
    return '$planVersionId:$year$month$day';
  }
}
