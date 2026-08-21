/// The amount field of the entry sheet: a real text field wearing the hero
/// numeral's clothes.
///
/// It replaced a custom on-screen numpad (owner's call, 2026-08-21). A real
/// field brings the platform's numeric keyboard, its caret, and — the reason
/// for the change — **select, copy and paste**, none of which a grid of
/// `GestureDetector`s can offer. What it must not lose is the look: oversized
/// tabular numerals, live grouping as you type, and a currency symbol that
/// leaves the number optically centred.
///
/// Everything locale-shaped is injected rather than read from `intl`'s ambient
/// default, which Flutter never sets.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import 'package:tally/data/providers.dart';

/// True for the ASCII digits `0`-`9` only.
///
/// Deliberately not `RegExp(r'\d')`, which also matches Arabic-Indic and
/// Devanagari digits: those would survive into the field and then fail to
/// parse, leaving a number on screen that the Save button says is invalid.
bool _isDigit(String ch) {
  final int c = ch.codeUnitAt(0);
  return c >= 0x30 && c <= 0x39;
}

/// Digits and at most one decimal marker, with the caret's position expressed
/// as "how many of those characters precede it".
///
/// Working in this canonical space is what keeps the caret sane: grouping
/// separators come and go on every keystroke, so an offset into the *displayed*
/// text means nothing a moment later.
class _Canonical {
  const _Canonical(this.whole, this.fraction, this.cursor);

  /// Digits before the decimal marker, ungrouped.
  final String whole;

  /// Digits after it, or null when no marker has been typed. Empty string
  /// means the marker is there with nothing after it yet (`12.`).
  final String? fraction;

  /// Significant characters before the caret.
  final int cursor;

  String get significant => fraction == null ? whole : '$whole.$fraction';

  /// Drops the significant character at [index] — how backspace over a group
  /// separator is turned into something that actually deletes.
  _Canonical removeAt(int index) {
    final String s = significant;
    if (index < 0 || index >= s.length) return this;
    final String next = s.substring(0, index) + s.substring(index + 1);
    final int marker = next.indexOf('.');
    return _Canonical(
      marker < 0 ? next : next.substring(0, marker),
      marker < 0 ? null : next.substring(marker + 1),
      cursor - 1,
    );
  }
}

/// Formats an amount as it is typed: digits only, one decimal separator, no
/// more decimals than the currency has, and live thousands grouping.
///
/// Anything else the platform hands over — a currency symbol, a stray letter,
/// the group separators inside a pasted `$1,234.56` — is dropped, which is
/// what makes pasting an amount out of another app work.
class AmountInputFormatter extends TextInputFormatter {
  AmountInputFormatter({
    required this.decimals,
    required this.groupSeparator,
    required this.decimalSeparator,
    this.maxWholeDigits = 12,
  });

  /// The currency's exponent: 2 for USD, 0 for UZS. Zero means the field
  /// refuses a decimal separator outright.
  final int decimals;

  final String groupSeparator;
  final String decimalSeparator;

  /// Cap on the integer part. Twelve digits of major units still convert to
  /// minor units well inside int64, so no amount that can be typed here can
  /// overflow on the way to the database.
  final int maxWholeDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    _Canonical next = _canonicalize(newValue);

    // Backspace over a group separator would otherwise be a dead key: the
    // separator is re-inserted by the grouping and the digits are unchanged,
    // so nothing appears to happen. Treat it as deleting the digit the
    // separator follows, which is what the user was aiming at.
    if (newValue.text.length < oldValue.text.length && next.cursor > 0) {
      final _Canonical previous = _canonicalize(oldValue);
      if (next.significant == previous.significant) {
        next = next.removeAt(next.cursor - 1);
      }
    }

    return _render(next);
  }

  /// Reduces a raw [TextEditingValue] to digits, one marker, and a caret
  /// counted in significant characters.
  _Canonical _canonicalize(TextEditingValue value) {
    final String text = value.text;
    final int caret = value.selection.end < 0
        ? text.length
        : value.selection.end.clamp(0, text.length);
    final String? marker = decimals == 0 ? null : _decimalCharIn(text);

    final StringBuffer whole = StringBuffer();
    String? fraction;
    int cursor = 0;

    for (int i = 0; i < text.length; i++) {
      final String ch = text[i];
      final bool beforeCaret = i < caret;
      if (_isDigit(ch)) {
        if (fraction == null) {
          if (whole.length >= maxWholeDigits) continue;
          whole.write(ch);
        } else {
          if (fraction.length >= decimals) continue;
          fraction += ch;
        }
        if (beforeCaret) cursor++;
      } else if (marker != null && ch == marker && fraction == null) {
        fraction = '';
        if (beforeCaret) cursor++;
      }
      // Everything else is dropped on purpose.
    }

    return _Canonical(whole.toString(), fraction, cursor);
  }

  /// Which of `.` / `,` is the decimal point in [text].
  ///
  /// When both appear the **last** one is it, which reads a pasted `1,234.56`
  /// and a pasted `1.234,56` correctly without knowing where either came from.
  /// A lone separator is the decimal point unless it is this locale's group
  /// separator — in English `1,234` is one thousand two hundred, not one and a
  /// bit.
  String? _decimalCharIn(String text) {
    final int lastDot = text.lastIndexOf('.');
    final int lastComma = text.lastIndexOf(',');
    if (lastDot < 0 && lastComma < 0) return null;
    if (lastDot >= 0 && lastComma >= 0) return lastDot > lastComma ? '.' : ',';
    final String only = lastDot >= 0 ? '.' : ',';
    return only == groupSeparator ? null : only;
  }

  /// Renders the canonical form as the grouped, localized text to display, and
  /// maps the caret back onto it.
  TextEditingValue _render(_Canonical value) {
    String whole = value.whole;
    int cursor = value.cursor;

    // Strip leading zeros so typing over a `0` does not leave `05`, but keep a
    // lone `0` so `0.50` can be typed at all. The stripped characters are
    // always the first ones, so anything the caret had counted among them
    // simply goes away with them.
    int stripped = 0;
    while (whole.length > 1 && whole.startsWith('0')) {
      whole = whole.substring(1);
      stripped++;
    }
    cursor = cursor > stripped ? cursor - stripped : 0;

    if (whole.isEmpty && value.fraction == null) {
      // An explicit collapsed caret, not the default `TextEditingValue.empty`:
      // that one carries offset -1, and handing an invalid selection back to
      // the field makes the next keystroke throw.
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    if (whole.isEmpty) {
      // A separator typed first: show `0,` rather than a bare separator, and
      // count the zero the caret now sits behind.
      whole = '0';
      cursor += 1;
    }

    final String text = value.fraction == null
        ? _group(whole)
        : '${_group(whole)}$decimalSeparator${value.fraction}';

    int offset = text.length;
    int seen = 0;
    for (int i = 0; i < text.length; i++) {
      if (seen >= cursor) {
        offset = i;
        break;
      }
      final String ch = text[i];
      if (_isDigit(ch) || ch == decimalSeparator) seen++;
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  /// Inserts [groupSeparator] every three digits from the right.
  ///
  /// Done by hand rather than through `NumberFormat` because the string can be
  /// longer than the value the field will accept and must never be routed
  /// through a number to be displayed.
  String _group(String digits) {
    if (digits.length <= 3 || groupSeparator.isEmpty) return digits;
    final StringBuffer out = StringBuffer();
    final int lead = digits.length % 3;
    if (lead != 0) out.write(digits.substring(0, lead));
    for (int i = lead; i < digits.length; i += 3) {
      if (out.isNotEmpty) out.write(groupSeparator);
      out.write(digits.substring(i, i + 3));
    }
    return out.toString();
  }

  /// Formats [canonical] (`"1234.5"`) as this formatter would display it —
  /// used to prefill the field when editing an existing entry, so the
  /// displayed value goes through exactly one code path.
  TextEditingValue format(String canonical) => _render(
    _canonicalize(
      TextEditingValue(
        text: canonical,
        selection: TextSelection.collapsed(offset: canonical.length),
      ),
    ),
  );
}

/// The ungrouped, dot-separated form of what the field shows — what
/// [parseAmountToMinor] expects.
///
/// Cannot be skipped by handing the displayed text straight to the parser: in
/// English the group separator is a comma, which the parser reads as a decimal
/// point, so `1,234` would parse as one and a bit.
String canonicalAmount(String shown, {required String decimalSeparator}) {
  final StringBuffer out = StringBuffer();
  bool marked = false;
  for (int i = 0; i < shown.length; i++) {
    final String ch = shown[i];
    if (_isDigit(ch)) {
      out.write(ch);
    } else if (ch == decimalSeparator && !marked) {
      marked = true;
      out.write('.');
    }
  }
  return out.toString();
}

/// The oversized amount input: currency symbol, hero numerals, platform
/// numeric keyboard, and the caret and selection handles that come with a real
/// field.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.currency,
    required this.kind,
    required this.locale,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String currency;

  /// Drives the sign and the colour: income gets a `+` in the accent, an
  /// expense and a transfer stay neutral ink — spending is normal life, and a
  /// transfer is the same money in a different pocket.
  final String kind;
  final String locale;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  /// Steps the hero size down as the number gets longer.
  ///
  /// A fixed size plus `FittedBox` is not available here — a text field needs a
  /// bounded width and cannot be scaled by its parent — so the ramp does the
  /// job `AdaptiveAmount` does elsewhere: shrink rather than truncate, because
  /// a clipped number is not a number.
  static double fontSizeFor(int length) {
    if (length <= 8) return 58;
    if (length <= 11) return 48;
    if (length <= 14) return 40;
    return 34;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final int decimals = decimalDigitsFor(currency);
    final String symbol = currencySymbolFor(currency, locale: locale);
    final bool isIncome = kind == Kind.income;
    final double fontSize = fontSizeFor(controller.text.length);

    final Widget symbolText = Padding(
      padding: EdgeInsets.only(top: fontSize * 0.16),
      child: Text(
        isIncome ? '+$symbol' : symbol,
        style: money(
          theme.headlineMedium!,
        ).copyWith(color: isIncome ? t.income : t.textSecondary),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // `mainAxisSize.min` plus a LOOSE `Flexible` around an `IntrinsicWidth`
      // field: the field asks for exactly the width of its text, so the symbol
      // and the number stay glued together as one centred unit, and the
      // Flexible's cap is what stops a very long number from overflowing —
      // past the cap the field scrolls its own text instead.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          symbolText,
          const SizedBox(width: 4),
          Flexible(
            child: IntrinsicWidth(
              child: TextField(
                controller: controller,
                autofocus: autofocus,
                textAlign: TextAlign.center,
                // `numberWithOptions` and not `phone`: a dialpad offers `+`, `*`
                // and `#`, none of which belong in an amount, and on iOS it has
                // no decimal key at all.
                keyboardType: TextInputType.numberWithOptions(
                  decimal: decimals > 0,
                  signed: false,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSubmitted?.call(),
                onChanged: onChanged,
                inputFormatters: <TextInputFormatter>[
                  AmountInputFormatter(
                    decimals: decimals,
                    groupSeparator: groupSeparatorFor(locale: locale),
                    decimalSeparator: decimalSeparatorFor(locale: locale),
                  ),
                ],
                style: money(
                  theme.displayLarge!,
                ).copyWith(fontSize: fontSize, color: t.textPrimary),
                cursorColor: t.accent,
                cursorWidth: 3,
                cursorRadius: const Radius.circular(2),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: '0',
                  hintStyle: money(theme.displayLarge!).copyWith(
                    fontSize: fontSize,
                    color: t.textSecondary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
