/// Money that shrinks and simplifies instead of overflowing.
///
/// The bug this guards: in a high-denomination currency (soʻm) every amount is
/// several times wider than the same figure in dollars, so dense rows either
/// adapt or render `15 360…`, which is not a number.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tally/features/common/adaptive_amount.dart';

const TextStyle _style = TextStyle(fontSize: 20, fontFamily: 'Roboto');

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required String text,
  String? fallback,
  double minScale = 0.7,
}) {
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: width,
          child: AdaptiveAmount(
            text,
            fallback: fallback,
            style: _style,
            minScale: minScale,
          ),
        ),
      ),
    ),
  );
}

/// The string actually rendered, and the font size it was rendered at.
({String text, double size}) _rendered(WidgetTester tester) {
  final Text widget = tester.widget<Text>(find.byType(Text));
  return (text: widget.data!, size: widget.style!.fontSize!);
}

void main() {
  testWidgets('an amount that fits is left completely alone', (tester) async {
    await _pump(tester, width: 400, text: r'$12.50', fallback: '12.50');
    final r = _rendered(tester);
    expect(r.text, r'$12.50');
    expect(r.size, 20);
  });

  testWidgets('a slightly-too-wide amount shrinks rather than truncating',
      (tester) async {
    await _pump(tester, width: 96, text: r'$1,234,567.89');
    final r = _rendered(tester);
    expect(r.text, r'$1,234,567.89', reason: 'the digits must all survive');
    expect(r.size, lessThan(20));
    expect(r.size, greaterThanOrEqualTo(20 * 0.7));
  });

  testWidgets('the shrunk text really does fit its box', (tester) async {
    // The regression: scaling by the predicted ratio alone left the text a
    // pixel or two too wide, which showed up as a stray ellipsis.
    await _pump(tester, width: 120, text: '15 360 000 000 soʻm');
    final Size size = tester.getSize(find.byType(Text));
    expect(size.width, lessThanOrEqualTo(120));
  });

  testWidgets('a far-too-wide amount drops the currency symbol instead of '
      'shrinking into unreadability', (tester) async {
    await _pump(
      tester,
      width: 90,
      text: '15 360 000 000 soʻm',
      fallback: '15 360 000 000',
    );
    final r = _rendered(tester);
    expect(r.text, '15 360 000 000');
    expect(r.size, greaterThanOrEqualTo(20 * 0.7),
        reason: 'the fallback should be readable, not micro-typed');
  });

  testWidgets('the full form is preferred whenever it fits at all',
      (tester) async {
    await _pump(
      tester,
      width: 300,
      text: r'$1,280.00',
      fallback: '1,280.00',
    );
    expect(_rendered(tester).text, r'$1,280.00');
  });

  testWidgets('with nothing left to try it degrades to the simplest form',
      (tester) async {
    await _pump(
      tester,
      width: 24,
      text: '15 360 000 000 soʻm',
      fallback: '15 360 000 000',
    );
    // Impossibly narrow: the simplest form at the floor, ellipsized by Text.
    final r = _rendered(tester);
    expect(r.text, '15 360 000 000');
    expect(r.size, closeTo(20 * 0.7, 0.001));
  });

  testWidgets('an unbounded width renders the preferred form untouched',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: <Widget>[
            AdaptiveAmount(r'$12.50', style: _style, fallback: '12.50'),
          ],
        ),
      ),
    );
    expect(_rendered(tester).text, r'$12.50');
  });
}
