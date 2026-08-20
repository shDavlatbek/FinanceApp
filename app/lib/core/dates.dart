/// Date helpers: month ranges, day/month grouping keys, and RFC3339 handling
/// for the `occurred_at` transaction field (stored as RFC3339 UTC strings).
library;

import 'package:intl/intl.dart';

String _pad2(int v) => v.toString().padLeft(2, '0');
String _pad4(int v) => v.toString().padLeft(4, '0');

/// First instant of the local month containing [d] (local midnight, day 1).
DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

/// First instant of the local month after the one containing [d].
DateTime nextMonthStart(DateTime d) => DateTime(d.year, d.month + 1);

/// [monthStart] shifted by [n] months (negative allowed).
DateTime addMonths(DateTime month, int n) =>
    DateTime(month.year, month.month + n);

/// `true` when [a] and [b] fall in the same local month.
bool isSameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

/// First instant of the local calendar day containing [d] (local midnight).
DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

/// First instant of the local day after the one containing [d].
///
/// Built with `DateTime(y, m, d + 1)` rather than `add(Duration(days: 1))` so
/// it stays exactly midnight across a daylight-saving transition, where a
/// local "day" is 23 or 25 hours long.
DateTime nextDayStart(DateTime d) => DateTime(d.year, d.month, d.day + 1);

/// [dayStart] shifted by [n] days (negative allowed), DST-safe for the same
/// reason as [nextDayStart].
DateTime addDays(DateTime day, int n) =>
    DateTime(day.year, day.month, day.day + n);

/// `true` when [a] and [b] fall on the same local calendar day.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Grouping key for a local month: `2026-08`.
String monthKey(DateTime d) => '${_pad4(d.year)}-${_pad2(d.month)}';

/// Grouping key for a local calendar day: `2026-08-19`.
String dayKey(DateTime d) => '${monthKey(d)}-${_pad2(d.day)}';

/// Human label for a month, e.g. `August 2026`.
///
/// Every label helper here takes the *selected* app locale explicitly:
/// `Intl.defaultLocale` is global mutable state that Flutter never sets, so a
/// bare `DateFormat` silently stays `en_US` forever.
String monthLabel(DateTime month, {String? locale}) =>
    DateFormat.yMMMM(locale).format(month);

/// Human label for a day group, e.g. `Tue, Aug 19`.
String dayLabel(DateTime day, {String? locale}) =>
    DateFormat.MMMEd(locale).format(day);

/// Short month name for chart axes, e.g. `Aug`.
String shortMonthLabel(DateTime month, {String? locale}) =>
    DateFormat.MMM(locale).format(month);

/// Short day + month, e.g. `Aug 19` — the entry sheet's custom-date chip.
String dayMonthLabel(DateTime day, {String? locale}) =>
    DateFormat.MMMd(locale).format(day);

/// Clock time, e.g. `4:05 PM` / `16:05`.
String timeLabel(DateTime instant, {String? locale}) =>
    DateFormat.jm(locale).format(instant);

/// Absolute date + time, e.g. `Aug 19, 2026 4:05 PM`.
String dateTimeLabel(DateTime instant, {String? locale}) =>
    DateFormat.yMMMd(locale).add_jm().format(instant);

/// Serializes an instant for the `occurred_at` field: RFC3339 UTC.
String toOccurredAt(DateTime instant) => instant.toUtc().toIso8601String();

/// Parses an `occurred_at` string into a local-time [DateTime].
DateTime occurredAtToLocal(String occurredAt) =>
    DateTime.parse(occurredAt).toLocal();

/// Local calendar-day grouping key for an `occurred_at` string.
String dayKeyFromOccurredAt(String occurredAt) =>
    dayKey(occurredAtToLocal(occurredAt));

/// SQL comparison bound for `occurred_at` columns.
///
/// Formats the UTC instant as `yyyy-MM-ddTHH:mm:ss` WITHOUT fraction or `Z`
/// so that `occurred_at >= bound` / `occurred_at < bound` string comparisons
/// are chronologically correct against any RFC3339 UTC value regardless of
/// its fractional-seconds precision.
String occurredAtQueryBound(DateTime localInstant) {
  final u = localInstant.toUtc();
  return '${_pad4(u.year)}-${_pad2(u.month)}-${_pad2(u.day)}'
      'T${_pad2(u.hour)}:${_pad2(u.minute)}:${_pad2(u.second)}';
}

/// `(startBound, endBound)` SQL bounds covering the local month of [month].
({String start, String end}) monthQueryBounds(DateTime month) => (
      start: occurredAtQueryBound(monthStart(month)),
      end: occurredAtQueryBound(nextMonthStart(month)),
    );

/// `(startBound, endBound)` SQL bounds covering the local calendar day of
/// [day] — the day-lens counterpart of [monthQueryBounds].
({String start, String end}) dayQueryBounds(DateTime day) => (
      start: occurredAtQueryBound(dayStart(day)),
      end: occurredAtQueryBound(nextDayStart(day)),
    );
