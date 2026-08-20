/// Stats — category donut with tappable slices synced to a legend, plus a
/// six-month income/expense trend, both month-navigable.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import '../common/cards.dart';
import '../common/count_up_amount.dart';
import '../common/empty_state.dart';
import '../common/kind_pill.dart';
import '../common/period_switcher.dart';
import 'package:tally/data/providers.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  String _kind = Kind.expense;
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final currency = ref.watch(currencyProvider).value ?? defaultCurrency;
    final totals = ref.watch(categoryTotalsByKindProvider(_kind)).value ??
        const <CategoryTotal>[];
    final mode = ref.watch(periodModeProvider);
    final trend =
        ref.watch(trendProvider).value ?? const <PeriodTotals>[];
    final periodStart = ref.watch(selectedPeriodStartProvider);

    final selected =
        _selected != null && _selected! < totals.length ? _selected : null;

    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
        children: [
          Text(l10n.statsTitle, style: theme.titleLarge),
          const SizedBox(height: 14),
          const Center(child: PeriodSwitcher()),
          const SizedBox(height: 10),
          const Center(child: PeriodModeToggle()),
          const SizedBox(height: 18),
          KindPill(
            value: _kind,
            onChanged: (k) => setState(() {
              _kind = k;
              _selected = null;
            }),
          ),
          const SizedBox(height: 18),
          if (totals.isEmpty)
            EmptyState(
              emoji: _kind == Kind.income ? '💼' : '🍩',
              title: l10n.statsNoDataTitle(
                  month: periodLabel(context,
                      mode: mode, start: periodStart)),
              message: _kind == Kind.income
                  ? l10n.statsNoIncomeMessage
                  : l10n.statsNoSpendingMessage,
              compact: true,
            )
          else
            TallyCard(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                children: [
                  _Donut(
                    totals: totals,
                    currency: currency,
                    kind: _kind,
                    selected: selected,
                    onSelect: (i) => setState(() =>
                        _selected = (i != null && i == _selected) ? null : i),
                  ),
                  const SizedBox(height: 12),
                  _Legend(
                    totals: totals,
                    currency: currency,
                    selected: selected,
                    onSelect: (i) => setState(
                        () => _selected = i == _selected ? null : i),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          SectionHeader(l10n.statsLastMonths(count: 6)),
          TallyCard(
            padding: const EdgeInsets.fromLTRB(14, 20, 14, 12),
            child: _TrendBars(
              periods: trend,
              mode: mode,
              currency: currency,
              selectedStart: periodStart,
              onSelect: (start) {
                HapticFeedback.selectionClick();
                switch (mode) {
                  case PeriodMode.day:
                    ref.read(selectedDayProvider.notifier).state =
                        dayStart(start);
                  case PeriodMode.month:
                    ref.read(selectedMonthProvider.notifier).state =
                        monthStart(start);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---- donut -----------------------------------------------------------------

class _Donut extends StatelessWidget {
  const _Donut({
    required this.totals,
    required this.currency,
    required this.kind,
    required this.selected,
    required this.onSelect,
  });

  final List<CategoryTotal> totals;
  final String currency;
  final String kind;
  final int? selected;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final locale = context.localeTag;
    final sum = totals.fold<int>(0, (s, e) => s + e.totalMinor);
    final sel = selected;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.scale(scale: 0.92 + 0.08 * v, child: child),
      ),
      child: SizedBox(
        height: 236,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: 3,
                centerSpaceRadius: 74,
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    if (event is! FlTapUpEvent) return;
                    final index =
                        response?.touchedSection?.touchedSectionIndex;
                    HapticFeedback.selectionClick();
                    onSelect(
                        index == null || index < 0 ? null : index);
                  },
                ),
                sections: [
                  for (final (i, ct) in totals.indexed)
                    PieChartSectionData(
                      value: ct.totalMinor.toDouble(),
                      color: colorFromHex(ct.category.color).withValues(
                        alpha: sel == null || sel == i ? 1.0 : 0.28,
                      ),
                      radius: sel == i ? 34 : 26,
                      showTitle: false,
                    ),
                ],
              ),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
            ),
            // Center total / selected slice.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Column(
                key: ValueKey(sel ?? -1),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sel == null
                        ? (kind == Kind.income
                            ? l10n.statsEarnedLabel
                            : l10n.statsSpentLabel)
                        : context
                            .categoryName(
                              id: totals[sel].category.id,
                              name: totals[sel].category.name,
                            )
                            .toUpperCase(),
                    style: theme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  CountUpAmount(
                    minor: sel == null ? sum : totals[sel].totalMinor,
                    format: (v) => formatMinor(v, currency, locale: locale),
                    style: theme.displaySmall!.copyWith(fontSize: 27),
                    duration: const Duration(milliseconds: 350),
                  ),
                  if (sel != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      sum == 0
                          ? ''
                          : l10n.statsSharePercent(
                              percent: (totals[sel].totalMinor / sum * 100)
                                  .round(),
                              emoji: totals[sel].category.emoji,
                            ),
                      style: theme.bodySmall!
                          .copyWith(color: t.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.totals,
    required this.currency,
    required this.selected,
    required this.onSelect,
  });

  final List<CategoryTotal> totals;
  final String currency;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final locale = context.localeTag;
    final sum = totals.fold<int>(0, (s, e) => s + e.totalMinor);

    return Column(
      children: [
        for (final (i, ct) in totals.indexed)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onSelect(i);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: selected == i
                    ? t.surfaceRaised
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorFromHex(ct.category.color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(ct.category.emoji,
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      context.categoryName(
                        id: ct.category.id,
                        name: ct.category.name,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyMedium!.copyWith(
                        fontWeight: selected == i
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    sum == 0
                        ? ''
                        : l10n.commonPercent(
                            value: (ct.totalMinor / sum * 100).round()),
                    style: money(theme.bodySmall!),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatMinor(ct.totalMinor, currency, locale: locale),
                    style: money(theme.bodyMedium!)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---- 6-month trend ------------------------------------------------------------

class _TrendBars extends StatefulWidget {
  const _TrendBars({
    required this.periods,
    required this.mode,
    required this.currency,
    required this.selectedStart,
    required this.onSelect,
  });

  /// Six months in the month lens, fourteen days in the day lens.
  final List<PeriodTotals> periods;
  final PeriodMode mode;
  final String currency;
  final DateTime selectedStart;
  final ValueChanged<DateTime> onSelect;

  /// `true` when [a] is the period the rest of the screen is showing.
  bool isSelected(DateTime a) => switch (mode) {
        PeriodMode.day => isSameDay(a, selectedStart),
        PeriodMode.month => isSameMonth(a, selectedStart),
      };

  @override
  State<_TrendBars> createState() => _TrendBarsState();
}

class _TrendBarsState extends State<_TrendBars> {
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entered = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final locale = context.localeTag;
    final per = minorUnitsPerMajor(widget.currency);

    double major(int minor) => minor / per;
    var maxVal = 0.0;
    for (final m in widget.periods) {
      if (major(m.incomeMinor) > maxVal) maxVal = major(m.incomeMinor);
      if (major(m.expenseMinor) > maxVal) maxVal = major(m.expenseMinor);
    }
    if (maxVal <= 0) maxVal = 1;

    return Column(
      children: [
        SizedBox(
          height: 168,
          child: BarChart(
            BarChartData(
              maxY: maxVal * 1.18,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxVal * 1.18 / 3,
                getDrawingHorizontalLine: (v) =>
                    FlLine(color: t.border, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= widget.periods.length) {
                        return const SizedBox.shrink();
                      }
                      final m = widget.periods[i].start;
                      final active = widget.isSelected(m);
                      // Fourteen day-of-month numbers fit where fourteen
                      // month names would not.
                      final label = widget.mode == PeriodMode.day
                          ? '${m.day}'
                          : shortMonthLabel(m, locale: locale);
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          label,
                          style: theme.labelMedium!.copyWith(
                            color: active
                                ? t.textPrimary
                                : t.textSecondary,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                enabled: true,
                handleBuiltInTouches: false,
                touchCallback: (event, response) {
                  if (event is! FlTapUpEvent) return;
                  final i = response?.spot?.touchedBarGroupIndex;
                  if (i != null && i >= 0 && i < widget.periods.length) {
                    widget.onSelect(widget.periods[i].start);
                  }
                },
              ),
              barGroups: [
                for (final (i, m) in widget.periods.indexed)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 3,
                    barRods: [
                      BarChartRodData(
                        toY: _entered ? major(m.expenseMinor) : 0,
                        width: 9,
                        borderRadius: BorderRadius.circular(3),
                        color: t.textPrimary.withValues(
                          alpha: widget.isSelected(m.start) ? 0.9 : 0.38,
                        ),
                      ),
                      BarChartRodData(
                        toY: _entered ? major(m.incomeMinor) : 0,
                        width: 9,
                        borderRadius: BorderRadius.circular(3),
                        color: t.accent.withValues(
                          alpha: widget.isSelected(m.start) ? 1.0 : 0.38,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendDot(context, t.textPrimary.withValues(alpha: 0.8),
                l10n.commonSpent),
            const SizedBox(width: 16),
            _legendDot(context, t.accent, l10n.commonIncome),
          ],
        ),
      ],
    );
  }

  Widget _legendDot(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelMedium!
                .copyWith(color: context.tokens.textSecondary)),
      ],
    );
  }
}
