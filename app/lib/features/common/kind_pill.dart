/// Segmented transaction-kind pill with a sliding accent thumb.
///
/// Two segments where only income and expense make sense (the Categories
/// screen — a category is one or the other), three where a transfer is also a
/// choice (the entry sheet). The thumb geometry is derived from the option
/// count rather than hard-coded, so neither call site can drift out of step
/// with what it renders.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import 'package:tally/data/providers.dart';

/// The two kinds a **category** may carry.
const List<String> kCategoryKindOptions = <String>[Kind.expense, Kind.income];

/// The three kinds a **transaction** may carry. A transfer belongs here and
/// nowhere near a category picker: it has no category by contract.
const List<String> kTransactionKindOptions = <String>[
  Kind.expense,
  Kind.income,
  Kind.transfer,
];

class KindPill extends StatelessWidget {
  const KindPill({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 44,
    this.options = kCategoryKindOptions,
  });

  /// The selected kind. Must be one of [options].
  final String value;
  final ValueChanged<String> onChanged;
  final double height;

  /// Which kinds this pill offers, left to right.
  final List<String> options;

  String _label(AppLocalizations l10n, String kind) => switch (kind) {
        Kind.expense => l10n.commonExpense,
        Kind.income => l10n.commonIncome,
        Kind.transfer => l10n.commonTransfer,
        _ => kind,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l10n = context.l10n;
    final labels = Theme.of(context).textTheme.labelLarge!;
    final int count = options.length;
    final int index = options.indexOf(value);

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
              // -1 is hard left, +1 hard right, so N segments land on
              // -1, …, +1 in equal steps. A single option (or an unknown
              // value) parks the thumb on the left rather than dividing by 0.
              alignment: Alignment(
                count < 2 || index < 0 ? -1 : -1 + 2 * index / (count - 1),
                0,
              ),
              child: Container(
                width: constraints.maxWidth / count,
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Row(
              children: [
                for (final String kind in options)
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
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              _label(l10n, kind),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
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
