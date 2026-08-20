/// Count-up money number (DESIGN.md motion: ~450 ms, easeOutCubic).
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'adaptive_amount.dart';

/// Animates between values whenever [minor] changes; formats every frame via
/// [format] so grouping/symbol stay live. Always tabular figures, and always
/// shrink-to-fit: hero numbers are the widest text in the app and a
/// high-denomination currency would otherwise run off the screen.
class CountUpAmount extends StatelessWidget {
  const CountUpAmount({
    super.key,
    required this.minor,
    required this.format,
    required this.style,
    this.duration = const Duration(milliseconds: 450),
    this.minScale = 0.45,
  });

  final int minor;
  final String Function(int minor) format;
  final TextStyle style;
  final Duration duration;

  /// Shrink floor, as a fraction of [style]'s font size.
  final double minScale;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: minor.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => AdaptiveAmount(
        format(value.round()),
        style: money(style),
        minScale: minScale,
        textAlign: TextAlign.center,
      ),
    );
  }
}
