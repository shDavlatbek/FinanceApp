/// Russian is the only locale here that needs four CLDR plural forms, and the
/// ICU parser only enforces `other` — so the forms are pinned by example.
///
/// CLDR (https://www.unicode.org/cldr/charts/47/supplemental/language_plural_rules.html):
///   ru one : 1, 21, 31, 101 …
///   ru few : 2–4, 22–24, 32–34 …
///   ru many: 0, 5–19, 100, 111 …
library;

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:tally/l10n/l10n.dart';

void main() {
  late AppLocalizations en;
  late AppLocalizations ru;
  late AppLocalizations uz;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    ru = await AppLocalizations.delegate.load(const Locale('ru'));
    uz = await AppLocalizations.delegate.load(const Locale('uz'));
  });

  group('Russian minutes-ago picks the right CLDR form', () {
    const Map<int, String> expected = <int, String>{
      1: '1 минуту назад', // one
      2: '2 минуты назад', // few
      5: '5 минут назад', // many
      21: '21 минуту назад', // one
      22: '22 минуты назад', // few
      111: '111 минут назад', // many
    };

    for (final MapEntry<int, String> e in expected.entries) {
      test('${e.key} -> ${e.value}', () {
        expect(ru.syncRelativeMinutesAgo(count: e.key), e.value);
      });
    }
  });

  group('Russian hours-ago picks the right CLDR form', () {
    const Map<int, String> expected = <int, String>{
      1: '1 час назад',
      2: '2 часа назад',
      5: '5 часов назад',
      21: '21 час назад',
      22: '22 часа назад',
      111: '111 часов назад',
    };

    for (final MapEntry<int, String> e in expected.entries) {
      test('${e.key} -> ${e.value}', () {
        expect(ru.syncRelativeHoursAgo(count: e.key), e.value);
      });
    }
  });

  test('Russian poll counter uses раз / раза / раз', () {
    expect(ru.driveWaitingChecked(count: 1), endsWith('1 раз)'));
    expect(ru.driveWaitingChecked(count: 2), endsWith('2 раза)'));
    expect(ru.driveWaitingChecked(count: 5), endsWith('5 раз)'));
    expect(ru.driveWaitingChecked(count: 21), endsWith('21 раз)'));
    expect(ru.driveWaitingChecked(count: 22), endsWith('22 раза)'));
    expect(ru.driveWaitingChecked(count: 111), endsWith('111 раз)'));
  });

  test('Russian month count uses месяц / месяца / месяцев', () {
    expect(ru.statsLastMonths(count: 1), 'Последний месяц');
    expect(ru.statsLastMonths(count: 2), 'Последние 2 месяца');
    expect(ru.statsLastMonths(count: 5), 'Последние 5 месяцев');
    expect(ru.statsLastMonths(count: 6), 'Последние 6 месяцев');
    expect(ru.statsLastMonths(count: 21), 'Последний месяц');
    expect(ru.statsLastMonths(count: 22), 'Последние 22 месяца');
    expect(ru.statsLastMonths(count: 111), 'Последние 111 месяцев');
  });

  test('English and Uzbek only need one/other', () {
    expect(en.syncRelativeMinutesAgo(count: 1), '1 min ago');
    expect(en.syncRelativeMinutesAgo(count: 22), '22 min ago');
    expect(en.statsLastMonths(count: 1), 'Last month');
    expect(en.statsLastMonths(count: 6), 'Last 6 months');

    expect(uz.syncRelativeMinutesAgo(count: 1), '1 daqiqa oldin');
    expect(uz.syncRelativeMinutesAgo(count: 5), '5 daqiqa oldin');
    expect(uz.syncRelativeMinutesAgo(count: 111), '111 daqiqa oldin');
    expect(uz.statsLastMonths(count: 1), 'Soʻnggi oy');
    expect(uz.statsLastMonths(count: 6), 'Soʻnggi 6 oy');
  });
}
