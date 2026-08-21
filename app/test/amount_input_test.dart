/// The amount field's input formatter.
///
/// This is the code that replaced the custom numpad, and it is where the
/// change can go wrong quietly: a formatter that mangles a paste, drops a
/// decimal, or parks the caret in the wrong place is worse than the numpad it
/// replaced. Every rule below is asserted against the caret as well as the
/// text, because the caret is what makes the field usable at all.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally/core/money.dart';
import 'package:tally/features/entry/amount_input.dart';

const String nbsp = ' ';

/// The formatter as English configures it: `.` decimal, `,` groups, 2 decimals.
AmountInputFormatter _en({int decimals = 2}) => AmountInputFormatter(
      decimals: decimals,
      groupSeparator: ',',
      decimalSeparator: '.',
    );

/// The formatter as Russian and Uzbek configure it: `,` decimal, no-break
/// space groups.
AmountInputFormatter _ru({int decimals = 2}) => AmountInputFormatter(
      decimals: decimals,
      groupSeparator: nbsp,
      decimalSeparator: ',',
    );

TextEditingValue _value(String text, [int? caret]) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret ?? text.length),
    );

/// Applies one edit and returns the result.
TextEditingValue _edit(
  AmountInputFormatter f, {
  required String from,
  int? fromCaret,
  required String to,
  int? toCaret,
}) =>
    f.formatEditUpdate(_value(from, fromCaret), _value(to, toCaret));

/// Types [keystrokes] one character at a time, appending at the caret, the way
/// a keyboard actually delivers them.
TextEditingValue _type(AmountInputFormatter f, String keystrokes) {
  // An explicit caret: `TextEditingValue.empty` starts at offset -1, which a
  // real field never hands to a formatter.
  TextEditingValue current = const TextEditingValue(
    text: '',
    selection: TextSelection.collapsed(offset: 0),
  );
  for (final String ch in keystrokes.split('')) {
    final int caret = current.selection.end;
    final String next = current.text.substring(0, caret) +
        ch +
        current.text.substring(caret);
    current = f.formatEditUpdate(current, _value(next, caret + 1));
  }
  return current;
}

void main() {
  group('typing', () {
    test('groups the whole part as it grows', () {
      expect(_type(_en(), '1').text, '1');
      expect(_type(_en(), '123').text, '123');
      expect(_type(_en(), '1234').text, '1,234');
      expect(_type(_en(), '1234567').text, '1,234,567');
    });

    test('uses the locale separators', () {
      expect(_type(_ru(), '1234567').text, '1${nbsp}234${nbsp}567');
      expect(_type(_ru(), '12,5').text, '12,5');
    });

    test('leaves the caret at the end of what was typed', () {
      final TextEditingValue v = _type(_en(), '1234');
      expect(v.text, '1,234');
      expect(v.selection.end, 5);
    });

    test('accepts one decimal separator and no more', () {
      expect(_type(_en(), '12.5').text, '12.5');
      expect(_type(_en(), '12.5.7').text, '12.57');
    });

    test('refuses more decimals than the currency has', () {
      expect(_type(_en(), '12.567').text, '12.56');
      // A zero-decimal currency refuses the separator outright: there are no
      // tiyin, so `12,5` soʻm is not a number the owner can mean.
      expect(_type(_en(decimals: 0), '12.5').text, '125');
      expect(_type(_ru(decimals: 0), '12,5').text, '125');
    });

    test('a separator typed first becomes a leading zero', () {
      final TextEditingValue v = _type(_en(), '.5');
      expect(v.text, '0.5');
      expect(v.selection.end, 3);
    });

    test('strips leading zeros but keeps a lone one', () {
      expect(_type(_en(), '0').text, '0');
      expect(_type(_en(), '05').text, '5');
      expect(_type(_en(), '000').text, '0');
      // The zero has to survive long enough to type `0.50`.
      expect(_type(_en(), '0.50').text, '0.50');
    });

    test('drops anything that is not a digit or a separator', () {
      // A hardware keyboard, or a keyboard app with letters on the numeric
      // layer, can deliver these.
      expect(_type(_en(), '1a2b3').text, '123');
      expect(_type(_en(), r'$12').text, '12');
    });

    test('caps the whole part instead of overflowing int64 later', () {
      // 12 digits of major units still convert to minor units well inside
      // int64, so nothing typeable here can overflow on the way to SQLite.
      final TextEditingValue v = _type(_en(), '12345678901234');
      expect(canonicalAmount(v.text, decimalSeparator: '.'), '123456789012');
      expect(
        parseAmountToMinor(
          canonicalAmount(v.text, decimalSeparator: '.'),
          currencyCode: 'USD',
        ),
        12345678901200,
      );
    });
  });

  group('pasting', () {
    test('reads an amount copied out of another app', () {
      expect(_edit(_en(), from: '', to: r'$1,234.56').text, '1,234.56');
      expect(_edit(_en(), from: '', to: '1 234.56').text, '1,234.56');
      expect(_edit(_en(), from: '', to: 'USD 99').text, '99');
    });

    test('reads a European-formatted amount too', () {
      // Both separators present: the LAST one is the decimal point, which
      // reads `1,234.56` and `1.234,56` correctly without being told which
      // convention wrote it.
      expect(_edit(_en(), from: '', to: '1.234,56').text, '1,234.56');
      expect(_edit(_ru(), from: '', to: '1,234.56').text, '1${nbsp}234,56');
    });

    test('an English group separator is not a decimal point', () {
      // The whole reason the group separator is injected: `1,234` in English
      // is one thousand two hundred, and reading it as `1.23` would understate
      // an amount by a factor of a thousand.
      expect(_edit(_en(), from: '', to: '1,234').text, '1,234');
      expect(
        parseAmountToMinor(
          canonicalAmount(_edit(_en(), from: '', to: '1,234').text,
              decimalSeparator: '.'),
          currencyCode: 'USD',
        ),
        123400,
      );
    });

    test('a lone comma IS a decimal point where that is the convention', () {
      expect(_edit(_ru(), from: '', to: '1234,5').text, '1${nbsp}234,5');
    });

    test('truncates a pasted amount to the currency exponent', () {
      expect(_edit(_en(), from: '', to: '12.3456').text, '12.34');
      // Zero decimals: the separator is not a separator, so the digits run
      // together into 1299 — and 1299 is grouped like any other number.
      expect(_edit(_en(decimals: 0), from: '', to: '12.99').text, '1,299');
    });
  });

  group('deleting', () {
    test('backspacing a digit regroups what is left', () {
      final TextEditingValue v =
          _edit(_en(), from: '1,234', to: '1,23', toCaret: 4);
      expect(v.text, '123');
      expect(v.selection.end, 3);
    });

    test('backspacing a group separator deletes the digit before it', () {
      // Regression guard: the naive formatter re-inserts the separator and
      // leaves the digits untouched, so the key looks broken. Here the caret
      // sits just after the comma in `1,234` and backspace removes it.
      final TextEditingValue v =
          _edit(_en(), from: '1,234', fromCaret: 2, to: '1234', toCaret: 1);
      expect(v.text, '234');
      expect(v.selection.end, 0);
    });

    test('clearing the field leaves it empty, not zero', () {
      // Empty is what shows the `0` hint; a literal `0` would be a value the
      // Save button then has to reject.
      expect(_edit(_en(), from: '1,234', to: '').text, '');
    });

    test('deleting the decimal separator merges the fraction back in', () {
      final TextEditingValue v =
          _edit(_en(), from: '12.34', fromCaret: 3, to: '1234', toCaret: 2);
      expect(v.text, '1,234');
    });
  });

  group('caret placement', () {
    test('an edit in the middle keeps the caret on the same digit', () {
      // `1,234` with the caret after the `2`; typing `9` there gives `12,934`
      // and the caret must land after the `9`, not at the end.
      final TextEditingValue v =
          _edit(_en(), from: '1,234', fromCaret: 3, to: '1,2934', toCaret: 4);
      expect(v.text, '12,934');
      expect(v.selection.end, 4);
      expect(v.text.substring(0, v.selection.end), '12,9');
    });

    test('the caret survives a separator appearing to its left', () {
      // Typing the 4th digit inserts a comma before the caret, so a caret kept
      // as a plain offset would end up one character short.
      final TextEditingValue v = _type(_en(), '1234');
      expect(v.selection.end, v.text.length);
    });
  });

  group('round trip to minor units', () {
    test('what the field shows parses to what was meant', () {
      for (final (String keys, String currency, int expected) in <
          (String, String, int)>[
        ('1234', 'USD', 123400),
        ('12.5', 'USD', 1250),
        ('0.05', 'USD', 5),
        ('15360000', 'UZS', 15360000),
      ]) {
        final int decimals = decimalDigitsFor(currency);
        final AmountInputFormatter f = AmountInputFormatter(
          decimals: decimals,
          groupSeparator: ',',
          decimalSeparator: '.',
        );
        final String shown = _type(f, keys).text;
        expect(
          parseAmountToMinor(
            canonicalAmount(shown, decimalSeparator: '.'),
            currencyCode: currency,
          ),
          expected,
          reason: 'typing "$keys" in $currency showed "$shown"',
        );
      }
    });

    test('the Russian display round-trips through the parser', () {
      final String shown = _type(_ru(), '1234567,89').text;
      expect(shown, '1${nbsp}234${nbsp}567,89');
      expect(
        parseAmountToMinor(
          canonicalAmount(shown, decimalSeparator: ','),
          currencyCode: 'RUB',
        ),
        123456789,
      );
    });
  });

  group('prefilling an existing amount', () {
    test('formats a stored value the way typing it would', () {
      expect(_en().format('1234.5').text, '1,234.5');
      expect(_ru().format('1234.5').text, '1${nbsp}234,5');
      expect(_en(decimals: 0).format('15360000').text, '15,360,000');
    });

    test('leaves the caret at the end, ready to edit', () {
      final TextEditingValue v = _en().format('1234.5');
      expect(v.selection.end, v.text.length);
    });
  });

  group('the hero size steps down instead of truncating', () {
    test('a longer number gets a smaller face', () {
      expect(AmountField.fontSizeFor(3), 58);
      expect(AmountField.fontSizeFor(8), 58);
      expect(AmountField.fontSizeFor(11), 48);
      expect(AmountField.fontSizeFor(14), 40);
      expect(AmountField.fontSizeFor(20), 34);
    });

    test('the ramp never grows with length', () {
      double previous = double.infinity;
      for (int i = 1; i <= 24; i++) {
        final double size = AmountField.fontSizeFor(i);
        expect(size, lessThanOrEqualTo(previous));
        previous = size;
      }
    });
  });
}
