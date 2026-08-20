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

/// Number of decimal digits for [currencyCode] (2 for USD/EUR, 0 for JPY, ...).
///
/// Deliberately locale-free: the exponent is a property of the ISO currency,
/// not of the language, and it is what converts minor units to major ones.
int decimalDigitsFor(String currencyCode) {
  final format = NumberFormat.currency(name: currencyCode.toUpperCase());
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
  final format = symbol
      ? NumberFormat.simpleCurrency(locale: locale, name: code)
      : NumberFormat.currency(locale: locale, name: code);
  final digits = format.decimalDigits ?? 2;
  return format.format(amountMinor / _pow10(digits));
}

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
