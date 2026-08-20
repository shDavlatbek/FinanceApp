/// Money helpers: integer minor units <-> formatted strings, user input parsing.
///
/// Amounts are stored as integer minor units (cents) per the contract.
library;

import 'package:intl/intl.dart';

import 'constants.dart';

int _pow10(int n) {
  var v = 1;
  for (var i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}

/// Currency exponents that MUST match the Go bot's table in
/// `server/internal/i18n/money.go`.
///
/// The exponent is the scale between a typed amount and the stored
/// `amount_minor`, so if the two peers disagree the same transaction reads
/// 100x apart on the two ends: `250` typed at the bot becomes 250 minor units
/// while the app reads it as 2.50. `test/currency_parity_test.dart` diffs this
/// map against the Go source to keep them honest.
///
/// UZS is the reason this table exists rather than trusting `intl`: ISO 4217
/// and CLDR both give it two decimals, but tiyin have been out of use for
/// decades and nobody in Uzbekistan writes `12 000,00 soʻm`. The bot already
/// treated it as zero-decimal; this is the side that was wrong.
const Map<String, int> kCurrencyExponents = <String, int>{
  'USD': 2,
  'EUR': 2,
  'GBP': 2,
  'RUB': 2,
  'UAH': 2,
  'KZT': 2,
  'TRY': 2,
  'INR': 2,
  'CNY': 2,
  'UZS': 0,
  'JPY': 0,
  'KRW': 0,
};

/// Number of decimal digits for [currencyCode] (2 for USD/EUR, 0 for UZS/JPY).
///
/// Deliberately locale-free: the exponent is a property of the ISO currency,
/// not of the language, and it is what converts minor units to major ones.
int decimalDigitsFor(String currencyCode) {
  final String code = currencyCode.toUpperCase();
  final int? shared = kCurrencyExponents[code];
  if (shared != null) return shared;
  final format = NumberFormat.currency(name: code);
  return format.decimalDigits ?? 2;
}

/// Minor units per major unit for [currencyCode] (100 for USD, 1 for JPY).
int minorUnitsPerMajor(String currencyCode) =>
    _pow10(decimalDigitsFor(currencyCode));

/// Formats [amountMinor] minor units as a currency string using
/// `intl.NumberFormat.currency` for the ISO [currencyCode].
///
/// [symbol] true -> locale symbol when known (`$1,234.50`), false -> ISO code
/// style (`USD 1,234.50`).
///
/// [locale] is the *selected* app locale (`en` / `ru` / `uz`) and drives the
/// decimal separator, the group separator and where the symbol sits — pass it
/// explicitly; `Intl.defaultLocale` is global mutable state and is `en_US`
/// until something sets it.
String formatMinor(
  int amountMinor,
  String currencyCode, {
  bool symbol = true,
  String? locale,
}) {
  final code = currencyCode.toUpperCase();
  final int digits = decimalDigitsFor(code);
  final format = symbol
      ? NumberFormat.simpleCurrency(
          locale: locale, name: code, decimalDigits: digits)
      : NumberFormat.currency(
          locale: locale, name: code, decimalDigits: digits);
  return format.format(_toMajor(amountMinor, digits));
}

/// Formats [amountMinor] with no currency symbol at all — `15 360 000` rather
/// than `15 360 000 soʻm`.
///
/// Used as the graceful degradation for dense rows: in a high-denomination
/// currency the symbol is what pushes an amount past the available width, and
/// dropping it is far better than ellipsizing a number into `15 360…`. The
/// currency is stated once on the hero total anyway.
String formatMinorPlain(
  int amountMinor,
  String currencyCode, {
  String? locale,
}) {
  final int digits = decimalDigitsFor(currencyCode.toUpperCase());
  final format = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: digits,
  );
  return format.format(_toMajor(amountMinor, digits));
}

/// Minor units -> major units for display.
///
/// Zero-decimal currencies skip the division entirely so the value never
/// becomes a double: those are exactly the currencies whose amounts get large
/// enough for float precision to start mattering.
num _toMajor(int amountMinor, int digits) =>
    digits == 0 ? amountMinor : amountMinor / _pow10(digits);

/// Formats with an explicit sign derived from the transaction [kind]:
/// income -> `+`, expense -> `−` (U+2212). Pass [signed] false to omit
/// the sign for income (expenses always keep the minus).
String formatSignedMinor(
  int amountMinor,
  String kind,
  String currencyCode, {
  bool symbol = true,
  bool signed = true,
  String? locale,
}) {
  final body = formatMinor(
    amountMinor.abs(),
    currencyCode,
    symbol: symbol,
    locale: locale,
  );
  if (kind == Kind.expense) return '−$body';
  // A transfer is neither a gain nor a loss — it is the same money in a
  // different pocket — so it never carries a sign.
  if (kind == Kind.transfer) return body;
  return signed ? '+$body' : body;
}

/// The currency symbol shown next to the amount (`$`, `₽`, `soʻm`), resolved
/// for [locale].
String currencySymbolFor(String currencyCode, {String? locale}) =>
    NumberFormat.simpleCurrency(
      locale: locale,
      name: currencyCode.toUpperCase(),
    ).currencySymbol;

/// Groups the whole part of a raw numpad string for [locale] (`1 234` in ru,
/// `1,234` in en). Used by the live amount display in the entry sheet.
String formatWholeGrouped(int whole, {String? locale}) =>
    NumberFormat('#,##0', locale).format(whole);

/// The decimal separator [locale] writes (`.` in en, `,` in ru and uz).
///
/// Raw numpad input is always kept canonical (`.`); this is only what the
/// numpad key and the live amount display *show*.
String decimalSeparatorFor({String? locale}) =>
    NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;

/// Parses free-form user input (`"250"`, `"250.50"`, `"250,50"`, `"1 234,5"`)
/// into minor units for [currencyCode].
///
/// Returns `null` when the input is not a valid positive amount:
/// non-numeric, zero, negative, or more decimals than the currency allows.
int? parseAmountToMinor(String input, {String currencyCode = defaultCurrency}) {
  final digits = decimalDigitsFor(currencyCode);
  var s = input.trim().replaceAll(' ', '').replaceAll(' ', '');
  if (s.isEmpty) return null;
  if (!RegExp(r'^\d+([.,]\d*)?$|^[.,]\d+$').hasMatch(s)) return null;
  s = s.replaceAll(',', '.');
  final parts = s.split('.');
  final wholeStr = parts[0].isEmpty ? '0' : parts[0];
  final fracStr = parts.length > 1 ? parts[1] : '';
  if (fracStr.length > digits) return null;
  final whole = int.tryParse(wholeStr);
  if (whole == null) return null;
  final frac = fracStr.isEmpty ? 0 : int.parse(fracStr.padRight(digits, '0'));
  final minor = whole * _pow10(digits) + frac;
  if (minor <= 0) return null;
  return minor;
}
