/// Designed empty state: emoji medallion + one-line warm copy.
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'buttons.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.emoji,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String emoji;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 20 : 44),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 64 : 88,
              height: compact ? 64 : 88,
              decoration: BoxDecoration(
                color: t.surfaceRaised,
                shape: BoxShape.circle,
                border: Border.all(color: t.border),
              ),
              child: Center(
                child: Text(emoji,
                    style: TextStyle(fontSize: compact ? 28 : 38)),
              ),
            ),
            SizedBox(height: compact ? 12 : 18),
            Text(title,
                style: theme.titleMedium!
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.bodySmall,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              // Wide enough for the longest translation of the call to
              // action, capped so it never spans the whole screen.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: SizedBox(
                  width: double.infinity,
                  child: AccentButton(
                      label: actionLabel!, onPressed: onAction, height: 48),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
