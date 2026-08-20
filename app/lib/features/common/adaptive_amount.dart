/// Numbers that shrink — and if need be simplify — to fit, instead of
/// overflowing or being cut in half.
///
/// A budget app has to render `15 360 000 soʻm` in the same slot that holds
/// `$12.50`. Zero-decimal, high-denomination currencies (UZS, IDR, VND) are
/// several times wider than USD at the same font size, so every money slot
/// either adapts or breaks.
///
/// Ellipsizing money is the one outcome worse than a small font — `15 360…` is
/// not a number, it is a lie — so the order of degradation is:
///
///   1. render [text] at full size,
///   2. shrink it, down to [minScale],
///   3. fall back to [fallback] (typically the same amount without its
///      currency symbol) and shrink that,
///   4. only then ellipsize.
library;

import 'package:flutter/material.dart';

class AdaptiveAmount extends StatelessWidget {
  const AdaptiveAmount(
    this.text, {
    super.key,
    required this.style,
    this.fallback,
    this.minScale = 0.7,
    this.textAlign,
  });

  final String text;

  /// A shorter rendering of the same value, used when [text] cannot fit above
  /// [minScale]. Null means "no simpler form exists".
  final String? fallback;

  final TextStyle style;

  /// Floor on the shrink, as a fraction of [style]'s font size.
  final double minScale;

  final TextAlign? textAlign;

  double _widthOf(BuildContext context, String value, TextStyle style) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: value, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final double width = painter.width;
    painter.dispose();
    return width;
  }

  TextStyle _scaled(double scale) => scale >= 1.0
      ? style
      : style.copyWith(
          fontSize: (style.fontSize ?? 14) * scale,
          // letterSpacing is absolute, not a multiple of the font size, so it
          // has to be scaled by hand or the shrunk text stays too wide.
          letterSpacing: style.letterSpacing == null
              ? null
              : style.letterSpacing! * scale,
        );

  /// The largest scale in [minScale]..1 at which [value] actually fits inside
  /// [usable], or null if even [minScale] does not.
  ///
  /// The first guess is measured rather than trusted: glyph hinting and letter
  /// spacing make rendered width slightly non-linear in font size, and being
  /// one pixel optimistic shows up as a stray ellipsis on an amount that looks
  /// like it fits.
  double? _fitScale(BuildContext context, String value, double usable) {
    double width = _widthOf(context, value, style);
    if (width <= usable) return 1.0;
    double scale = width <= 0 ? 1.0 : (usable / width);
    for (int i = 0; i < 6 && scale >= minScale; i++) {
      width = _widthOf(context, value, _scaled(scale));
      if (width <= usable) return scale;
      scale *= 0.97;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || maxWidth <= 0) {
          return _text(text, style);
        }
        final double usable = maxWidth - 1;

        final List<String> candidates = <String>[
          text,
          if (fallback != null && fallback != text) fallback!,
        ];

        for (final String candidate in candidates) {
          final double? scale = _fitScale(context, candidate, usable);
          if (scale != null) return _text(candidate, _scaled(scale));
        }
        // Nothing fits even at the floor: render the simplest form as small as
        // allowed and let it ellipsize.
        return _text(candidates.last, _scaled(minScale));
      },
    );
  }

  Widget _text(String value, TextStyle effective) => Text(
        value,
        style: effective,
        textAlign: textAlign,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );
}
