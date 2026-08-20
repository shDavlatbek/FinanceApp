/// Cross-language guard: the app and the Telegram bot must agree on how many
/// minor units a typed amount becomes.
///
/// The exponent is the scale between "250" as typed and `amount_minor` as
/// stored, so a disagreement makes the same transaction read 100x apart on the
/// two peers — the bot logs `250` as 250 minor units while the app renders
/// those 250 units as `2.50`. This test diffs the Dart table against the Go
/// source that owns the other half of the contract.
///
/// UZS is exactly why this exists: ISO 4217 and CLDR both give it two decimal
/// digits, so `intl` reports 2, but tiyin are long out of use and the bot has
/// always treated so'm as zero-decimal.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tally/core/money.dart';

/// Parses `"USD": {exp: 2, symbol: "$"},` lines out of the Go table.
Map<String, int> _goExponents() {
  final File source =
      File('../server/internal/i18n/money.go');
  if (!source.existsSync()) {
    fail('Go currency table not found at ${source.absolute.path}');
  }
  final RegExp entry = RegExp(r'"([A-Z]{3})":\s*\{exp:\s*(\d+)');
  final Map<String, int> found = <String, int>{};
  for (final RegExpMatch m in entry.allMatches(source.readAsStringSync())) {
    found[m.group(1)!] = int.parse(m.group(2)!);
  }
  return found;
}

void main() {
  test('the Go bot table and the Dart table list the same currencies', () {
    final Map<String, int> go = _goExponents();
    expect(go, isNotEmpty, reason: 'failed to parse the Go currency table');
    expect(
      go.keys.toSet(),
      kCurrencyExponents.keys.toSet(),
      reason: 'a currency exists on one peer only; add it to both',
    );
  });

  test('every shared currency has the same exponent on both peers', () {
    final Map<String, int> go = _goExponents();
    for (final MapEntry<String, int> e in go.entries) {
      expect(
        kCurrencyExponents[e.key],
        e.value,
        reason: '${e.key}: Go says ${e.value} decimals, the app says '
            '${kCurrencyExponents[e.key]} — the peers would disagree by '
            '10^${(e.value - (kCurrencyExponents[e.key] ?? 0)).abs()}',
      );
    }
  });

  test('decimalDigitsFor honours the shared table over intl', () {
    // The regression this table was added for: intl reports 2 for UZS.
    expect(decimalDigitsFor('UZS'), 0);
    expect(decimalDigitsFor('uzs'), 0);
    expect(decimalDigitsFor('JPY'), 0);
    expect(decimalDigitsFor('KRW'), 0);
    expect(decimalDigitsFor('USD'), 2);
    expect(decimalDigitsFor('RUB'), 2);
    // Codes outside the table still fall back to intl rather than guessing.
    expect(decimalDigitsFor('CHF'), 2);
  });

  test('a zero-decimal currency neither shows nor parses decimals', () {
    expect(formatMinor(12000, 'UZS', locale: 'uz'), isNot(contains(',00')));
    expect(formatMinorPlain(12000, 'UZS', locale: 'uz'),
        isNot(contains(',00')));
    // 12000 so'm typed at the bot and typed in the app must store the same
    // number of minor units.
    expect(parseAmountToMinor('12000', currencyCode: 'UZS'), 12000);
    expect(parseAmountToMinor('12000', currencyCode: 'USD'), 1200000);
    // Tiyin do not exist, so a fractional so'm is not a valid amount.
    expect(parseAmountToMinor('12000,50', currencyCode: 'UZS'), isNull);
  });

  test('zero-decimal formatting keeps full integer precision', () {
    // Above 2^53 a double would round; a zero-decimal currency is exactly
    // where amounts get big enough for that to matter.
    const int big = 9007199254740993;
    expect(formatMinorPlain(big, 'UZS', locale: 'en'), contains('9,007,199'));
    expect(formatMinorPlain(big, 'UZS', locale: 'en'), endsWith('993'));
  });

  test('the plain form drops the symbol but keeps the grouping', () {
    final String withSymbol = formatMinor(153600000, 'UZS', locale: 'uz');
    final String plain = formatMinorPlain(153600000, 'UZS', locale: 'uz');
    expect(withSymbol.length, greaterThan(plain.length));
    expect(plain, isNot(contains('m')));
    expect(plain.replaceAll(' ', ' '), '153 600 000');
  });
}
