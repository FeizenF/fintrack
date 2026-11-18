import 'date_range.dart';

/// Bucket size used by the report charts.
enum ReportGranularity { day, month }

/// Request key for the report's grouped time series.
class ReportSeriesRequest {
  const ReportSeriesRequest({required this.range, required this.granularity});

  final DateRange range;
  final ReportGranularity granularity;

  @override
  bool operator ==(Object other) =>
      other is ReportSeriesRequest &&
      other.range == range &&
      other.granularity == granularity;

  @override
  int get hashCode => Object.hash(range, granularity);
}

/// Pick a bucket size that keeps the chart readable: day buckets for ranges up
/// to ~2 months, month buckets for longer ranges.
ReportGranularity granularityFor(DateRange range) =>
    range.days <= 62 ? ReportGranularity.day : ReportGranularity.month;

/// Matching preceding period for the selected report filter.
DateRange previousReportRange(DateRange current, PeriodFilter filter) {
  final DateTime start = current.start;
  return switch (filter) {
    PeriodFilter.today => DateRange.day(
      start.subtract(const Duration(days: 1)),
    ),
    PeriodFilter.thisWeek => DateRange.week(
      start.subtract(const Duration(days: 1)),
    ),
    PeriodFilter.thisMonth => DateRange.month(
      DateTime(start.year, start.month - 1),
    ),
    PeriodFilter.thisYear => DateRange.year(DateTime(start.year - 1)),
    PeriodFilter.custom => DateRange(
      start: current.start.subtract(current.duration),
      end: current.start,
    ),
  };
}

/// Normalised bucket start for [value] at [granularity].
DateTime bucketOf(DateTime value, ReportGranularity granularity) =>
    switch (granularity) {
      ReportGranularity.day => DateTime(value.year, value.month, value.day),
      ReportGranularity.month => DateTime(value.year, value.month),
    };

/// Every bucket covered by [range], in chronological order.
List<DateTime> bucketsFor(DateRange range, ReportGranularity granularity) {
  final List<DateTime> buckets = <DateTime>[];
  DateTime cursor = bucketOf(range.start, granularity);
  while (cursor.isBefore(range.end)) {
    buckets.add(cursor);
    cursor = switch (granularity) {
      ReportGranularity.day => DateTime(
        cursor.year,
        cursor.month,
        cursor.day + 1,
      ),
      ReportGranularity.month => DateTime(cursor.year, cursor.month + 1),
    };
  }
  return buckets;
}

/// One point of the income/expense series.
class PeriodSeriesPoint {
  const PeriodSeriesPoint({
    required this.bucket,
    required this.income,
    required this.expense,
  });

  final DateTime bucket;
  final int income;
  final int expense;

  int get net => income - expense;
}

/// Orders [points] by bucket and fills every gap in [range] with zeros, so a
/// chart never draws a misleading continuous line across missing periods.
List<PeriodSeriesPoint> completeSeries({
  required DateRange range,
  required ReportGranularity granularity,
  required List<PeriodSeriesPoint> points,
}) {
  final Map<DateTime, PeriodSeriesPoint> byBucket =
      <DateTime, PeriodSeriesPoint>{};
  for (final PeriodSeriesPoint point in points) {
    byBucket[bucketOf(point.bucket, granularity)] = point;
  }

  return bucketsFor(range, granularity)
      .map(
        (DateTime bucket) =>
            byBucket[bucket] ??
            PeriodSeriesPoint(bucket: bucket, income: 0, expense: 0),
      )
      .toList(growable: false);
}

/// Growth of [current] against [previous] in percent.
///
/// Returns `null` when [previous] is zero: a percentage against nothing would be
/// meaningless, so the UI shows "belum ada pembanding" instead.
double? percentChange({required int current, required int previous}) {
  if (previous == 0) return null;
  return ((current - previous) / previous) * 100;
}
