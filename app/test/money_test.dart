import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:tally/core/money.dart';

void main() {
  setUpAll(() {
    Intl.defaultLocale = 'en_US';
  });

  group('parseAmountToMinor', () {
    test('plain integer', () {
      expect(parseAmountToMinor('250'), 25000);
    });

    test('dot decimals', () {
      expect(parseAmountToMinor('250.50'), 25050);
      expect(parseAmountToMinor('0.01'), 1);
      expect(parseAmountToMinor('250.5'), 25050);
    });

    test('comma decimals', () {
      expect(parseAmountToMinor('250,50'), 25050);
      expect(parseAmountToMinor('1,5'), 150);
    });

    test('leading separator and trailing separator', () {
      expect(parseAmountToMinor('.5'), 50);
      expect(parseAmountToMinor(',5'), 50);
      expect(parseAmountToMinor('250.'), 25000);
    });

    test('whitespace tolerated', () {
      expect(parseAmountToMinor(' 250.50 '), 25050);
      expect(parseAmountToMinor('1 234,50'), 123450);
    });

    test('rejects invalid input', () {
      expect(parseAmountToMinor(''), isNull);
      expect(parseAmountToMinor('abc'), isNull);
      expect(parseAmountToMinor('12a'), isNull);
      expect(parseAmountToMinor('-5'), isNull);
      expect(parseAmountToMinor('+5'), isNull);
      expect(parseAmountToMinor('1.2.3'), isNull);
      expect(parseAmountToMinor('1,2,3'), isNull);
    });

    test('rejects zero', () {
      expect(parseAmountToMinor('0'), isNull);
      expect(parseAmountToMinor('0.00'), isNull);
      expect(parseAmountToMinor('0,0'), isNull);
    });

    test('rejects more decimals than the currency allows', () {
      expect(parseAmountToMinor('1.234'), isNull);
      expect(parseAmountToMinor('1.23'), 123);
    });

    test('zero-decimal currency (JPY)', () {
      expect(parseAmountToMinor('250', currencyCode: 'JPY'), 250);
      expect(parseAmountToMinor('250.5', currencyCode: 'JPY'), isNull);
    });
  });

  group('formatMinor', () {
    test('USD with symbol', () {
      expect(formatMinor(25050, 'USD'), r'$250.50');
      expect(formatMinor(123456789, 'USD'), r'$1,234,567.89');
    });

    test('USD without symbol uses ISO code style', () {
      expect(formatMinor(25050, 'USD', symbol: false), contains('250.50'));
      expect(formatMinor(25050, 'USD', symbol: false), contains('USD'));
    });

    test('JPY has no decimals', () {
      expect(formatMinor(250, 'JPY'), '¥250');
    });

    test('round trip', () {
      const currency = 'USD';
      final minor = parseAmountToMinor('1234.56', currencyCode: currency);
      expect(minor, 123456);
      expect(formatMinor(minor!, currency), r'$1,234.56');
    });
  });

  group('formatSignedMinor', () {
    test('expense gets U+2212 minus', () {
      expect(formatSignedMinor(25000, 'expense', 'USD'), '−\$250.00');
    });

    test('income gets plus when signed', () {
      expect(formatSignedMinor(5000000, 'income', 'USD'), '+\$50,000.00');
      expect(
        formatSignedMinor(5000000, 'income', 'USD', signed: false),
        '\$50,000.00',
      );
    });
  });

  group('helpers', () {
    test('decimalDigitsFor / minorUnitsPerMajor', () {
      expect(decimalDigitsFor('USD'), 2);
      expect(minorUnitsPerMajor('USD'), 100);
      expect(decimalDigitsFor('JPY'), 0);
      expect(minorUnitsPerMajor('JPY'), 1);
    });
  });
}
