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

/// Short month + year, e.g. `Aug 2026` — the period bar, which shares its row
/// with the lens toggle and has no space for the month spelled out.
String shortMonthYearLabel(DateTime month, {String? locale}) =>
    DateFormat.yMMM(locale).format(month);

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

/// The `occurred_at` calendar date in **UTC**, `yyyy-MM-dd` — the CSV export's
/// `date` column (docs/ARCHITECTURE.md § CSV export).
///
/// UTC, not local, because the contract pins the column that way: a spreadsheet
/// row has to mean the same thing on every machine that opens the file, and the
/// exporting phone's offset is not part of the data.
String utcDayKeyFromOccurredAt(String occurredAt) {
  final DateTime u = DateTime.parse(occurredAt).toUtc();
  return '${_pad4(u.year)}-${_pad2(u.month)}-${_pad2(u.day)}';
}

/// `YYYYMMDD-HHMMSS` stamp for an export file name, in **local** time.
///
/// Local on purpose: this string exists to be read by the owner in a file
/// listing, and a backup they made at 9pm should not be filed under yesterday.
String fileStamp(DateTime instant) =>
    '${_pad4(instant.year)}${_pad2(instant.month)}${_pad2(instant.day)}'
    '-${_pad2(instant.hour)}${_pad2(instant.minute)}${_pad2(instant.second)}';

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

/// `(startBound, endBound)` SQL bounds covering the inclusive local day range
/// [from]..[to] — the range-lens counterpart of [monthQueryBounds]. The end
/// bound is the midnight *after* [to], so the last day is fully included.
({String start, String end}) rangeQueryBounds(DateTime from, DateTime to) => (
      start: occurredAtQueryBound(dayStart(from)),
      end: occurredAtQueryBound(nextDayStart(to)),
    );

/// Number of whole days in the inclusive range [from]..[to] (1 when they are
/// the same day).
///
/// Compares UTC-normalized midnights on purpose: `DateTime.difference` measures
/// absolute elapsed time, so a local 23-hour DST day would otherwise report a
/// one-day gap as zero.
int daysInRange(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays +
    1;

/// Clamps a range so `from` never sits after `to`, swapping them if it does.
({DateTime from, DateTime to}) normalizeRange(DateTime from, DateTime to) {
  final a = dayStart(from);
  final b = dayStart(to);
  return a.isAfter(b) ? (from: b, to: a) : (from: a, to: b);
}

/// Label for a day range: `Aug 19` for a single day, `1 – Aug 20` when both
/// ends share a month, `Aug 28 – Sep 3` otherwise.
///
/// The default is deliberately terse because the period pill shares one row
/// with the lens toggle. Pass [compact] false where there is room for both
/// ends in full, such as the hero caption.
String rangeLabel(
  DateTime from,
  DateTime to, {
  String? locale,
  bool compact = true,
}) {
  final r = normalizeRange(from, to);
  if (isSameDay(r.from, r.to)) return dayMonthLabel(r.from, locale: locale);
  if (compact && r.from.year == r.to.year && r.from.month == r.to.month) {
    return '${r.from.day} – ${dayMonthLabel(r.to, locale: locale)}';
  }
  return '${dayMonthLabel(r.from, locale: locale)} – '
      '${dayMonthLabel(r.to, locale: locale)}';
}

/// `(startBound, endBound)` SQL bounds covering the local calendar day of
/// [day] — the day-lens counterpart of [monthQueryBounds].
({String start, String end}) dayQueryBounds(DateTime day) => (
      start: occurredAtQueryBound(dayStart(day)),
      end: occurredAtQueryBound(nextDayStart(day)),
    );
