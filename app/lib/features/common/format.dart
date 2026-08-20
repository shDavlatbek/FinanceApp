/// Small formatting helpers shared by screens.
///
/// Everything here takes the selected locale explicitly (and the relative-time
/// helper takes `AppLocalizations` too) so money and dates follow the language
/// the user picked, not the device locale.
library;

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../l10n/l10n.dart';

/// `−$12.50` for negative, `$12.50` for zero/positive (hero style).
String netMoney(int minor, String currency, {String? locale}) => minor < 0
    ? '−${formatMinor(-minor, currency, locale: locale)}'
    : formatMinor(minor, currency, locale: locale);

/// `+$12.50` / `−$12.50` — always signed (day subtotals).
String signedNetMoney(int minor, String currency, {String? locale}) =>
    (minor < 0 ? '−' : '+') +
    formatMinor(minor.abs(), currency, locale: locale);

/// Localized "last synced" label: `just now`, `22 min ago`, `3 h ago`, or an
/// absolute date/time once the gap passes a day.
///
/// [now] is injectable so tests are not clock-dependent.
String relativeTime(
  AppLocalizations l10n,
  int unixMs, {
  String? locale,
  DateTime? now,
}) {
  final DateTime then = DateTime.fromMillisecondsSinceEpoch(unixMs);
  final Duration diff = (now ?? DateTime.now()).difference(then);
  if (diff.inSeconds < 60) return l10n.syncRelativeJustNow;
  if (diff.inMinutes < 60) {
    return l10n.syncRelativeMinutesAgo(count: diff.inMinutes);
  }
  if (diff.inHours < 24) return l10n.syncRelativeHoursAgo(count: diff.inHours);
  return dateTimeLabel(then, locale: locale);
}
