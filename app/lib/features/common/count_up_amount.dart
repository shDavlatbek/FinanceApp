/// Count-up money number (DESIGN.md motion: ~450 ms, easeOutCubic).
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Animates between values whenever [minor] changes; formats every frame via
/// [format] so grouping/symbol stay live. Always tabular figures.
class CountUpAmount extends StatelessWidget {
  const CountUpAmount({
    super.key,
    required this.minor,
    required this.format,
    required this.style,
    this.duration = const Duration(milliseconds: 450),
  });

  final int minor;
  final String Function(int minor) format;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: minor.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => Text(
        format(value.round()),
        maxLines: 1,
        style: money(style),
      ),
    );
  }
}
