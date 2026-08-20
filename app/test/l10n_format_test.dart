/// Money and dates must follow the SELECTED locale, not the device locale.
///
/// `Intl.defaultLocale` is null and `Intl.systemLocale` is hard-coded to
/// `en_US`, so a `NumberFormat`/`DateFormat` built without an explicit locale
/// silently stays American forever. These tests pin the per-locale output of
/// every helper the UI calls, and deliberately leave `Intl.defaultLocale`
/// unset so a regression to the ambient default fails here.
library;

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:tally/core/dates.dart';
import 'package:tally/core/money.dart';
import 'package:tally/features/common/format.dart';
import 'package:tally/l10n/l10n.dart';

/// U+00A0 no-break space — the group separator ru and uz use for numbers, and
/// the gap before a trailing currency symbol.
const String nbsp = ' ';

/// U+202F narrow no-break space — CLDR puts it before `PM` in en and before
/// the `г.` year marker in ru.
const String nnbsp = ' ';

void main() {
  setUpAll(() async {
    // Needed only outside a Localizations scope (a pure-Dart test);
    // GlobalMaterialLocalizations does this for the running app.
    await initializeDateFormatting();
    Intl.defaultLocale = null;
  });

  group('money follows the selected locale', () {
    test('en — symbol prefix, comma groups, dot decimals', () {
      expect(formatMinor(123456789, 'USD', locale: 'en'), r'$1,234,567.89');
      expect(formatMinor(25050, 'USD', locale: 'en'), r'$250.50');
      expect(formatMinor(250, 'JPY', locale: 'en'), '¥250');
    });

    test('ru — symbol suffix, NBSP groups, comma decimals', () {
      expect(
        formatMinor(123456789, 'USD', locale: 'ru'),
        '1${nbsp}234${nbsp}567,89$nbsp\$',
      );
      expect(
        formatMinor(123456789, 'RUB', locale: 'ru'),
        '1${nbsp}234${nbsp}567,89$nbsp₽',
      );
    });

    test('uz — symbol suffix, NBSP groups, and NO decimals for soʻm', () {
      // UZS is zero-decimal to match the Telegram bot (see
      // currency_parity_test.dart): 123456789 minor units IS 123 456 789 soʻm,
      // not 1 234 567,89. intl reports two decimals for UZS, which is where
      // the two peers used to disagree by 100x.
      expect(
        formatMinor(123456789, 'UZS', locale: 'uz'),
        '123${nbsp}456${nbsp}789${nbsp}soʼm',
      );
      // A two-decimal currency still formats the uz way.
      expect(
        formatMinor(123456789, 'USD', locale: 'uz'),
        '1${nbsp}234${nbsp}567,89$nbsp\$',
      );
    });

    test('signed amounts keep the locale formatting', () {
      expect(
        formatSignedMinor(25000, 'expense', 'USD', locale: 'en'),
        '−\$250.00',
      );
      expect(
        formatSignedMinor(25000, 'income', 'RUB', locale: 'ru'),
        '+250,00$nbsp₽',
      );
      expect(netMoney(-25000, 'RUB', locale: 'ru'), '−250,00$nbsp₽');
      expect(signedNetMoney(25000, 'RUB', locale: 'ru'), '+250,00$nbsp₽');
    });

    test('the currency symbol is resolved per locale', () {
      expect(currencySymbolFor('USD', locale: 'en'), r'$');
      expect(currencySymbolFor('RUB', locale: 'ru'), '₽');
      expect(currencySymbolFor('UZS', locale: 'uz'), 'soʼm');
    });

    test('the live numpad grouping follows the locale', () {
      expect(formatWholeGrouped(1234567, locale: 'en'), '1,234,567');
      expect(
          formatWholeGrouped(1234567, locale: 'ru'), '1${nbsp}234${nbsp}567');
      expect(
          formatWholeGrouped(1234567, locale: 'uz'), '1${nbsp}234${nbsp}567');
    });

    test('the numpad decimal key shows the locale separator', () {
      expect(decimalSeparatorFor(locale: 'en'), '.');
      expect(decimalSeparatorFor(locale: 'ru'), ',');
      expect(decimalSeparatorFor(locale: 'uz'), ',');
    });
  });

  group('dates follow the selected locale', () {
    final DateTime day = DateTime(2026, 8, 19, 16, 5);

    test('en', () {
      expect(monthLabel(day, locale: 'en'), 'August 2026');
      expect(dayLabel(day, locale: 'en'), 'Wed, Aug 19');
      expect(shortMonthLabel(day, locale: 'en'), 'Aug');
      expect(dayMonthLabel(day, locale: 'en'), 'Aug 19');
      expect(timeLabel(day, locale: 'en'), '4:05${nnbsp}PM');
    });

    test('ru', () {
      expect(monthLabel(day, locale: 'ru'), 'август 2026$nnbsp' 'г.');
      expect(dayLabel(day, locale: 'ru'), 'ср, 19 авг.');
      expect(shortMonthLabel(day, locale: 'ru'), 'авг.');
      expect(dayMonthLabel(day, locale: 'ru'), '19 авг.');
      expect(timeLabel(day, locale: 'ru'), '16:05');
    });

    test('uz', () {
      expect(monthLabel(day, locale: 'uz'), 'avgust, 2026');
      expect(dayLabel(day, locale: 'uz'), 'Chor, 19-avg');
      expect(shortMonthLabel(day, locale: 'uz'), 'Avg');
      expect(dayMonthLabel(day, locale: 'uz'), '19-avg');
      expect(timeLabel(day, locale: 'uz'), '16:05');
    });

    test('a bare helper call is NOT silently en_US', () {
      // Guard against a future refactor dropping the locale argument: en and
      // ru must not agree on a month name.
      expect(
          monthLabel(day, locale: 'ru'), isNot(monthLabel(day, locale: 'en')));
    });
  });

  group('relative "last synced" label', () {
    final DateTime now = DateTime(2026, 8, 19, 16, 5);

    Future<String> label(String locale, Duration ago) async {
      final AppLocalizations l10n =
          await AppLocalizations.delegate.load(Locale(locale));
      return relativeTime(
        l10n,
        now.subtract(ago).millisecondsSinceEpoch,
        locale: locale,
        now: now,
      );
    }

    test('under a minute', () async {
      expect(await label('en', const Duration(seconds: 5)), 'just now');
      expect(await label('ru', const Duration(seconds: 5)), 'только что');
      expect(await label('uz', const Duration(seconds: 5)), 'hozirgina');
    });

    test('minutes use the locale plural', () async {
      expect(await label('en', const Duration(minutes: 22)), '22 min ago');
      expect(await label('ru', const Duration(minutes: 22)), '22 минуты назад');
      expect(await label('ru', const Duration(minutes: 5)), '5 минут назад');
      expect(await label('uz', const Duration(minutes: 22)), '22 daqiqa oldin');
    });

    test('hours use the locale plural', () async {
      expect(await label('en', const Duration(hours: 3)), '3 h ago');
      expect(await label('ru', const Duration(hours: 3)), '3 часа назад');
      expect(await label('ru', const Duration(hours: 11)), '11 часов назад');
    });

    test('over a day falls back to an absolute, localized date', () async {
      expect(
        await label('en', const Duration(days: 2)),
        'Aug 17, 2026 4:05${nnbsp}PM',
      );
      expect(
        await label('ru', const Duration(days: 2)),
        '17 авг. 2026$nnbsp' 'г. 16:05',
      );
    });
  });
}
