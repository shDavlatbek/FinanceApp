/// One transaction row: emoji medallion, category, time and note, signed amount.
///
/// A transfer is rendered differently on purpose: it carries no category, so
/// it shows the two accounts it moves between and an UNSIGNED amount in the
/// neutral ink. Falling through the category path would label it
/// "Uncategorized" and print a green "+", i.e. money the owner never earned.
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
    final isTransfer = tx.kind == Kind.transfer;
    final accounts = isTransfer
        ? ref.watch(accountsByIdProvider)
        : const <String, Account>{};

    String accountLabel(String id) {
      final Account? a = accounts[id];
      if (a == null) return '—';
      return context.accountName(id: a.id, name: a.name);
    }

    final categoryColor = isTransfer
        ? t.textSecondary
        : (category != null ? colorFromHex(category.color) : t.textSecondary);
    final when = occurredAtToLocal(tx.occurredAt);
    final subtitleParts = [
      if (isTransfer)
        l10n.transactionTransferRoute(
          from: accountLabel(tx.accountId),
          to: accountLabel(tx.toAccountId),
        ),
      // The time always shows: it is what orders a day, so hiding it behind
      // "only when there is no note" made the order look arbitrary.
      timeLabel(when, locale: locale),
      if (tx.note.isNotEmpty) tx.note,
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
                  child: Text(
                      isTransfer ? '🔄' : (category?.emoji ?? '❓'),
                      style: const TextStyle(fontSize: 19)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTransfer
                          ? l10n.transactionTransfer
                          : (category == null
                              ? l10n.transactionUncategorized
                              : context.categoryName(
                                  id: category.id,
                                  name: category.name,
                                )),
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
                  color: isTransfer
                      ? t.textSecondary
                      : (isIncome ? t.income : t.expense),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
