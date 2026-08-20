/// One transaction row: emoji medallion, category, note/time, signed amount.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import 'package:tally/data/providers.dart';

class TransactionTile extends ConsumerWidget {
  const TransactionTile({super.key, required this.tx, this.onTap});

  final Transaction tx;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final locale = context.localeTag;
    final category = ref.watch(categoriesByIdProvider)[tx.categoryId];
    final currency = ref.watch(currencyProvider).value ?? defaultCurrency;

    final categoryColor =
        category != null ? colorFromHex(category.color) : t.textSecondary;
    final when = occurredAtToLocal(tx.occurredAt);
    final subtitleParts = [
      if (tx.note.isNotEmpty) tx.note else timeLabel(when, locale: locale),
      if (tx.source == TxSource.telegram) l10n.sourceTelegram,
    ];
    final isIncome = tx.kind == Kind.income;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: Text(category?.emoji ?? '❓',
                      style: const TextStyle(fontSize: 19)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category == null
                          ? l10n.transactionUncategorized
                          : context.categoryName(
                              id: category.id,
                              name: category.name,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyLarge!
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                formatSignedMinor(
                  tx.amountMinor,
                  tx.kind,
                  currency,
                  locale: locale,
                ),
                style: money(theme.bodyLarge!).copyWith(
                  fontWeight: FontWeight.w700,
                  color: isIncome ? t.income : t.expense,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
