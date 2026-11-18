import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/utils/date_range.dart';
import 'package:fintrack/core/utils/report_series.dart';

void main() {
  group('granularityFor', () {
    test('short ranges are grouped per day', () {
      expect(
        granularityFor(DateRange.month(DateTime(2026, 5))),
        ReportGranularity.day,
      );
      expect(
        granularityFor(DateRange.week(DateTime(2026, 5, 17))),
        ReportGranularity.day,
      );
      expect(
        granularityFor(
          DateRange.inclusive(DateTime(2026, 5, 1), DateTime(2026, 6, 10)),
        ),
        ReportGranularity.day,
      );
    });

    test('long ranges are grouped per month', () {
      expect(
        granularityFor(DateRange.year(DateTime(2026, 5))),
        ReportGranularity.month,
      );
      expect(
        granularityFor(
          DateRange.inclusive(DateTime(2026, 1, 1), DateTime(2026, 7, 1)),
        ),
        ReportGranularity.month,
      );
    });
  });

  group('bucketsFor', () {
    test('day buckets cover every day of the range', () {
      final List<DateTime> buckets = bucketsFor(
        DateRange.inclusive(DateTime(2026, 5, 1), DateTime(2026, 5, 3)),
        ReportGranularity.day,
      );
      expect(buckets, <DateTime>[
        DateTime(2026, 5, 1),
        DateTime(2026, 5, 2),
        DateTime(2026, 5, 3),
      ]);
    });

    test('month buckets follow calendar months across a year boundary', () {
      final List<DateTime> buckets = bucketsFor(
        DateRange.inclusive(DateTime(2025, 11, 20), DateTime(2026, 2, 3)),
        ReportGranularity.month,
      );
      expect(buckets, <DateTime>[
        DateTime(2025, 11),
        DateTime(2025, 12),
        DateTime(2026, 1),
        DateTime(2026, 2),
      ]);
    });
  });

  group('completeSeries', () {
    test('fills missing buckets with zero totals in chronological order', () {
      final DateRange range = DateRange.inclusive(
        DateTime(2026, 5, 1),
        DateTime(2026, 5, 4),
      );
      final List<PeriodSeriesPoint> series = completeSeries(
        range: range,
        granularity: ReportGranularity.day,
        points: <PeriodSeriesPoint>[
          PeriodSeriesPoint(
            bucket: DateTime(2026, 5, 3),
            income: 200000,
            expense: 50000,
          ),
        ],
      );

      expect(series, hasLength(4));
      expect(
        series.every(
          (PeriodSeriesPoint point) =>
              point.income == 0 || point.bucket.day == 3,
        ),
        isTrue,
      );
      expect(series[2].bucket, DateTime(2026, 5, 3));
      expect(series[2].income, 200000);
      expect(series[2].expense, 50000);
      expect(series[2].net, 150000);
      expect(series[0].income, 0);
      expect(series[3].expense, 0);
    });

    test('ignores buckets outside the range', () {
      final List<PeriodSeriesPoint> series = completeSeries(
        range: DateRange.month(DateTime(2026, 5)),
        granularity: ReportGranularity.month,
        points: <PeriodSeriesPoint>[
          PeriodSeriesPoint(
            bucket: DateTime(2026, 4),
            income: 900000,
            expense: 0,
          ),
        ],
      );

      expect(series, hasLength(1));
      expect(series.single.bucket, DateTime(2026, 5));
      expect(series.single.income, 0);
    });
  });

  group('percentChange', () {
    test('reports growth against the previous period', () {
      expect(percentChange(current: 150000, previous: 100000), 50);
      expect(percentChange(current: 50000, previous: 100000), -50);
      expect(percentChange(current: 100000, previous: 100000), 0);
    });

    test('is keyed by range and granularity', () {
      final ReportSeriesRequest first = ReportSeriesRequest(
        range: DateRange.month(DateTime(2026, 5)),
        granularity: ReportGranularity.day,
      );
      final ReportSeriesRequest equal = ReportSeriesRequest(
        range: DateRange.month(DateTime(2026, 5)),
        granularity: ReportGranularity.day,
      );
      final ReportSeriesRequest different = ReportSeriesRequest(
        range: DateRange.month(DateTime(2026, 6)),
        granularity: ReportGranularity.day,
      );

      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
      expect(first, isNot(different));
    });

    test('has no percentage when the previous period was empty', () {
      expect(percentChange(current: 150000, previous: 0), isNull);
      expect(percentChange(current: 0, previous: 0), isNull);
    });
  });

  group('previousReportRange', () {
    test('month filter looks at the previous calendar month', () {
      final DateRange current = DateRange.month(DateTime(2026, 1, 9));
      final DateRange previous = previousReportRange(
        current,
        PeriodFilter.thisMonth,
      );

      expect(previous.start, DateTime(2025, 12));
      expect(previous.end, DateTime(2026, 1));
    });

    test('year filter looks at the previous calendar year', () {
      final DateRange previous = previousReportRange(
        DateRange.year(DateTime(2026, 5)),
        PeriodFilter.thisYear,
      );

      expect(previous.start, DateTime(2025));
      expect(previous.end, DateTime(2026));
    });

    test('custom filter keeps the same duration directly before the range', () {
      final DateRange current = DateRange.inclusive(
        DateTime(2026, 3, 5),
        DateTime(2026, 3, 14),
      );
      final DateRange previous = previousReportRange(
        current,
        PeriodFilter.custom,
      );

      expect(previous.end, current.start);
      expect(previous.duration, current.duration);
      expect(previous.start, DateTime(2026, 2, 23));
    });
  });
}
