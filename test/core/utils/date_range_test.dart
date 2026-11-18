import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/core/utils/date_range.dart';

void main() {
  group('DateRange', () {
    test('day range covers exactly one day', () {
      final DateRange range = DateRange.day(DateTime(2026, 5, 17, 14, 30));
      expect(range.start, DateTime(2026, 5, 17));
      expect(range.end, DateTime(2026, 5, 18));
      expect(range.days, 1);
      expect(range.contains(DateTime(2026, 5, 17, 23, 59)), isTrue);
      expect(range.contains(DateTime(2026, 5, 18)), isFalse);
    });

    test('week range starts on Monday', () {
      // 2026-05-17 is a Sunday.
      final DateRange range = DateRange.week(DateTime(2026, 5, 17));
      expect(range.start, DateTime(2026, 5, 11));
      expect(range.end, DateTime(2026, 5, 18));
      expect(range.days, 7);
    });

    test('month range handles december rollover', () {
      final DateRange range = DateRange.month(DateTime(2026, 12, 9));
      expect(range.start, DateTime(2026, 12, 1));
      expect(range.end, DateTime(2027, 1, 1));
    });

    test('year range spans the full year', () {
      final DateRange range = DateRange.year(DateTime(2026, 7, 4));
      expect(range.start, DateTime(2026, 1, 1));
      expect(range.end, DateTime(2027, 1, 1));
    });

    test('inclusive range includes the whole end day', () {
      final DateRange range = DateRange.inclusive(
        DateTime(2026, 1, 5, 9),
        DateTime(2026, 1, 7, 20),
      );
      expect(range.start, DateTime(2026, 1, 5));
      expect(range.end, DateTime(2026, 1, 8));
      expect(range.contains(DateTime(2026, 1, 7, 23, 30)), isTrue);
    });

    test('equality is value based', () {
      expect(
        DateRange.inclusive(DateTime(2026, 1, 1), DateTime(2026, 1, 2)),
        DateRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 3)),
      );
    });
  });

  group('PeriodFilter', () {
    final DateTime now = DateTime(2026, 5, 17, 12);

    test('resolves each preset against a reference date', () {
      expect(PeriodFilter.today.resolve(now: now).start, DateTime(2026, 5, 17));
      expect(
        PeriodFilter.thisWeek.resolve(now: now).start,
        DateTime(2026, 5, 11),
      );
      expect(
        PeriodFilter.thisMonth.resolve(now: now).start,
        DateTime(2026, 5, 1),
      );
      expect(
        PeriodFilter.thisYear.resolve(now: now).start,
        DateTime(2026, 1, 1),
      );
    });

    test('custom filter uses the supplied range', () {
      final DateRange custom = DateRange.inclusive(
        DateTime(2025, 12, 1),
        DateTime(2026, 1, 31),
      );
      expect(
        PeriodFilter.custom.resolve(now: now, customRange: custom),
        custom,
      );
    });

    test('every filter has a label', () {
      for (final PeriodFilter filter in PeriodFilter.values) {
        expect(filter.label, isNotEmpty);
      }
    });
  });
}
