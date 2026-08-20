/// Home — the selected period at a glance: hero net number (count-up),
/// income/spent chips, the period switcher and its `Day · Month` lens toggle,
/// staggered per-category spending bars, and the period's transactions (the
/// five most recent in the month lens, the whole day in the day lens).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import '../common/animated_item_list.dart';
import '../common/cards.dart';
import '../common/count_up_amount.dart';
import '../common/empty_state.dart';
import '../common/format.dart';
import '../common/period_switcher.dart';
import '../common/sync_indicator.dart';
import '../common/transaction_tile.dart';
import '../entry/entry_sheet.dart';
import 'package:tally/data/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final locale = context.localeTag;
    final mode = ref.watch(periodModeProvider);
    final periodStart = ref.watch(selectedPeriodStartProvider);
    final currency = ref.watch(currencyProvider).value ?? defaultCurrency;
    final totals = ref.watch(periodTotalsProvider).value;
    final categoryTotals = ref.watch(periodCategoryTotalsProvider).value ??
        const <CategoryTotal>[];
    final recent =
        ref.watch(periodTransactionsProvider).value ?? const <Transaction>[];

    final now = DateTime.now();
    final isCurrentPeriod = switch (mode) {
      PeriodMode.day => isSameDay(periodStart, now),
      PeriodMode.month => isSameMonth(periodStart, now),
    };
    // The hero caption names the period unless it is the current one, where
    // "NET THIS MONTH" / "NET TODAY" reads better than repeating the date.
    final heroCaption = switch ((mode, isCurrentPeriod)) {
      (PeriodMode.day, true) => l10n.homeNetToday,
      (PeriodMode.day, false) => l10n.homeNetForDay(
          date: dayLabel(periodStart, locale: locale).toUpperCase(),
        ),
      (PeriodMode.month, true) => l10n.homeNetThisMonth,
      (PeriodMode.month, false) => l10n.homeNetForMonth(
          month: monthLabel(periodStart, locale: locale).toUpperCase(),
        ),
    };
    final showEmpty = totals != null &&
        totals.incomeMinor == 0 &&
        totals.expenseMinor == 0 &&
        recent.isEmpty;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => ref.read(syncEngineProvider).syncNow(),
        edgeOffset: 12,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ---- top bar ------------------------------------------
                  Row(
                    children: [
                      Text(l10n.appTitle,
                          style: theme.titleLarge!
                              .copyWith(letterSpacing: -0.8)),
                      const Spacer(),
                      const SyncIndicator(),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // ---- hero ---------------------------------------------
                  Center(
                    child: Column(
                      children: [
                        Text(
                          heroCaption,
                          textAlign: TextAlign.center,
                          style: theme.labelSmall,
                        ),
                        const SizedBox(height: 10),
                        CountUpAmount(
                          minor: totals?.netMinor ?? 0,
                          format: (v) =>
                              netMoney(v, currency, locale: locale),
                          style: theme.displayLarge!,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _CaptionChip(
                              dotColor: t.income,
                              label: l10n.commonIncome,
                              amount: formatMinor(
                                totals?.incomeMinor ?? 0,
                                currency,
                                locale: locale,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _CaptionChip(
                              dotColor: t.textSecondary,
                              label: l10n.commonSpent,
                              amount: formatMinor(
                                totals?.expenseMinor ?? 0,
                                currency,
                                locale: locale,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Center(child: PeriodSwitcher()),
                  const SizedBox(height: 10),
                  const Center(child: PeriodModeToggle()),
                  const SizedBox(height: 28),

                  // ---- content ------------------------------------------
                  if (showEmpty)
                    EmptyState(
                      emoji: '🌱',
                      title: l10n.homeEmptyTitle,
                      message: l10n.homeEmptyMessage,
                      actionLabel: l10n.commonAddEntry,
                      onAction: () => showEntrySheet(context),
                    )
                  else ...[
                    SectionHeader(l10n.homeSpendingSection),
                    if (categoryTotals.isEmpty)
                      EmptyState(
                        emoji: '🍃',
                        title: mode == PeriodMode.day
                            ? l10n.homeNothingSpentDayTitle
                            : l10n.homeNothingSpentTitle,
                        message: mode == PeriodMode.day
                            ? l10n.homeNothingSpentDayMessage
                            : l10n.homeNothingSpentMessage,
                        compact: true,
                      )
                    else
                      TallyCard(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                        child: CategoryBars(
                          totals: categoryTotals,
                          currency: currency,
                        ),
                      ),
                    const SizedBox(height: 24),
                    SectionHeader(
                      mode == PeriodMode.day
                          ? l10n.homeDayEntriesSection
                          : l10n.homeRecentSection,
                      trailing: TextButton(
                        onPressed: () => context.go('/history'),
                        child: Text(l10n.commonAll),
                      ),
                    ),
                    if (recent.isEmpty)
                      EmptyState(
                        emoji: '🧾',
                        title: l10n.homeNoEntriesTitle,
                        message: l10n.homeNoEntriesMessage,
                        compact: true,
                      )
                    else
                      TallyCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: AnimatedItemList<Transaction>(
                          items: recent,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          keyOf: (tx) => tx.id,
                          itemBuilder: (context, tx) => TransactionTile(
                            tx: tx,
                            onTap: () =>
                                showEntrySheet(context, existing: tx),
                          ),
                        ),
                      ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- caption chip ------------------------------------------------------------

class _CaptionChip extends StatelessWidget {
  const _CaptionChip({
    required this.dotColor,
    required this.label,
    required this.amount,
  });

  final Color dotColor;
  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration:
                BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(label,
              style:
                  theme.labelMedium!.copyWith(color: t.textSecondary)),
          const SizedBox(width: 6),
          Text(amount,
              style: money(theme.labelMedium!)
                  .copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ---- staggered category bars ---------------------------------------------------

/// Spending bars that grow in with ~40 ms staggered delays on entry
/// (DESIGN.md motion) and animate width changes implicitly afterwards.
class CategoryBars extends StatefulWidget {
  const CategoryBars({
    super.key,
    required this.totals,
    required this.currency,
  });

  final List<CategoryTotal> totals;
  final String currency;

  @override
  State<CategoryBars> createState() => _CategoryBarsState();
}

class _CategoryBarsState extends State<CategoryBars>
    with SingleTickerProviderStateMixin {
  static const _grow = Duration(milliseconds: 450);
  static const _staggerMs = 40;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _totalDuration);
    _controller.forward();
  }

  Duration get _totalDuration => Duration(
      milliseconds:
          _grow.inMilliseconds + _staggerMs * (widget.totals.length - 1).clamp(0, 20));

  @override
  void didUpdateWidget(covariant CategoryBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds =
        oldWidget.totals.map((e) => e.category.id).join(',');
    final newIds = widget.totals.map((e) => e.category.id).join(',');
    if (oldIds != newIds) {
      // New month / re-ranked set: replay the staggered entrance.
      _controller.duration = _totalDuration;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final maxMinor = widget.totals.isEmpty
        ? 1
        : widget.totals
            .map((e) => e.totalMinor)
            .reduce((a, b) => a > b ? a : b);
    final sumMinor = widget.totals.fold<int>(0, (s, e) => s + e.totalMinor);
    final totalMs = _totalDuration.inMilliseconds;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Column(
        children: [
          for (final (i, ct) in widget.totals.indexed) ...[
            if (i > 0) const SizedBox(height: 14),
            _bar(
              context,
              t,
              theme,
              ct,
              fraction: ct.totalMinor / maxMinor,
              share: sumMinor == 0 ? 0 : ct.totalMinor / sumMinor,
              enter: CurvedAnimation(
                parent: _controller,
                curve: Interval(
                  (i * _staggerMs / totalMs).clamp(0.0, 0.99),
                  ((i * _staggerMs + _grow.inMilliseconds) / totalMs)
                      .clamp(0.01, 1.0),
                  curve: Curves.easeOutCubic,
                ),
              ).value,
            ),
          ],
        ],
      ),
    );
  }

  Widget _bar(
    BuildContext context,
    TallyTokens t,
    TextTheme theme,
    CategoryTotal ct, {
    required double fraction,
    required double share,
    required double enter,
  }) {
    final color = colorFromHex(ct.category.color);
    return Opacity(
      opacity: (0.35 + 0.65 * enter).clamp(0.0, 1.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(ct.category.emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.categoryName(
                    id: ct.category.id,
                    name: ct.category.name,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodyMedium!
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                context.l10n.commonPercent(value: (share * 100).round()),
                style: money(theme.bodySmall!),
              ),
              const SizedBox(width: 10),
              Text(
                formatMinor(
                  ct.totalMinor,
                  widget.currency,
                  locale: context.localeTag,
                ),
                style: money(theme.bodyMedium!)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 7),
          LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Container(
                  height: 6,
                  width: constraints.maxWidth,
                  decoration: BoxDecoration(
                    color: t.surfaceRaised,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  height: 6,
                  width: (constraints.maxWidth * fraction * enter)
                      .clamp(0.0, constraints.maxWidth),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
