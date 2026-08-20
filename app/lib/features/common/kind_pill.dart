/// Expense / Income segmented pill with a sliding accent thumb.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import 'package:tally/data/providers.dart';

class KindPill extends StatelessWidget {
  const KindPill({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 44,
  });

  /// `Kind.expense` or `Kind.income`.
  final String value;
  final ValueChanged<String> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l10n = context.l10n;
    final isExpense = value == Kind.expense;
    final labels = Theme.of(context).textTheme.labelLarge!;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment:
                  isExpense ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                width: constraints.maxWidth / 2,
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Row(
              children: [
                for (final (kind, label) in [
                  (Kind.expense, l10n.commonExpense),
                  (Kind.income, l10n.commonIncome),
                ])
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (kind != value) {
                          HapticFeedback.selectionClick();
                          onChanged(kind);
                        }
                      },
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: labels.copyWith(
                            fontWeight: FontWeight.w700,
                            color: value == kind
                                ? t.onAccent
                                : t.textSecondary,
                          ),
                          child: Text(label),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
