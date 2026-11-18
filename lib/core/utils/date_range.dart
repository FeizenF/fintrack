/// Half-open date range [start, end) used by dashboard, reports and filters.
class DateRange {
  const DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  factory DateRange.day(DateTime date) {
    final DateTime from = DateTime(date.year, date.month, date.day);
    return DateRange(start: from, end: from.add(const Duration(days: 1)));
  }

  factory DateRange.week(DateTime date) {
    final DateTime day = DateTime(date.year, date.month, date.day);
    // Monday as first day of week.
    final DateTime monday = day.subtract(Duration(days: day.weekday - 1));
    return DateRange(start: monday, end: monday.add(const Duration(days: 7)));
  }

  factory DateRange.month(DateTime date) => DateRange(
        start: DateTime(date.year, date.month),
        end: DateTime(date.year, date.month + 1),
      );

  factory DateRange.year(DateTime date) =>
      DateRange(start: DateTime(date.year), end: DateTime(date.year + 1));

  factory DateRange.inclusive(DateTime from, DateTime to) => DateRange(
        start: DateTime(from.year, from.month, from.day),
        end: DateTime(to.year, to.month, to.day).add(const Duration(days: 1)),
      );

  Duration get duration => end.difference(start);

  int get days => duration.inDays;

  bool contains(DateTime value) =>
      !value.isBefore(start) && value.isBefore(end);

  DateRange copyWith({DateTime? start, DateTime? end}) =>
      DateRange(start: start ?? this.start, end: end ?? this.end);

  @override
  String toString() => 'DateRange($start -> $end)';

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Selectable dashboard/report period.
enum PeriodFilter {
  today,
  thisWeek,
  thisMonth,
  thisYear,
  custom;

  String get label => switch (this) {
        PeriodFilter.today => 'Hari ini',
        PeriodFilter.thisWeek => 'Minggu ini',
        PeriodFilter.thisMonth => 'Bulan ini',
        PeriodFilter.thisYear => 'Tahun ini',
        PeriodFilter.custom => 'Rentang khusus',
      };

  /// Resolves the filter into a concrete range. [custom] falls back to [now]
  /// when no explicit range is supplied.
  DateRange resolve({DateTime? now, DateRange? customRange}) {
    final DateTime reference = now ?? DateTime.now();
    return switch (this) {
      PeriodFilter.today => DateRange.day(reference),
      PeriodFilter.thisWeek => DateRange.week(reference),
      PeriodFilter.thisMonth => DateRange.month(reference),
      PeriodFilter.thisYear => DateRange.year(reference),
      PeriodFilter.custom =>
        customRange ?? DateRange.month(reference),
    };
  }
}
