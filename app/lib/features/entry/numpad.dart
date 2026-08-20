/// Custom numpad — no system keyboard, haptic feedback on every key
/// (DESIGN.md motion: `HapticFeedback.lightImpact`).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

class Numpad extends StatelessWidget {
  const Numpad({
    super.key,
    required this.onDigit,
    required this.onDecimal,
    required this.onBackspace,
    required this.onClear,
    this.decimalEnabled = true,
    this.decimalLabel = '.',
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onDecimal;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final bool decimalEnabled;

  /// What the decimal key shows — the locale's separator (`.` / `,`). Input is
  /// still stored canonically with a dot.
  final String decimalLabel;

  @override
  Widget build(BuildContext context) {
    Widget digit(String d) => _NumKey(
          child: Text(d),
          onTap: () => onDigit(d),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: [for (final d in row) Expanded(child: digit(d))]),
        Row(
          children: [
            Expanded(
              child: _NumKey(
                enabled: decimalEnabled,
                onTap: onDecimal,
                child: Text(decimalLabel),
              ),
            ),
            Expanded(child: digit('0')),
            Expanded(
              child: _NumKey(
                onTap: onBackspace,
                onLongPress: onClear,
                child: const Icon(Icons.backspace_outlined, size: 22),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NumKey extends StatelessWidget {
  const _NumKey({
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = money(Theme.of(context).textTheme.headlineSmall!).copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: enabled ? t.textPrimary : t.textSecondary.withValues(alpha: 0.3),
    );
    return SizedBox(
      height: 62,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onTap();
                }
              : null,
          onLongPress: onLongPress == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  onLongPress!();
                },
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: IconTheme(
              data: IconThemeData(color: style.color, size: 22),
              child: DefaultTextStyle(style: style, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
