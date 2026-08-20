/// The period bar on Home and Stats: a pill that pages through the selected
/// day / month / range and opens a picker when tapped, with the lens toggle
/// sitting on the same line.
///
/// The toggle is a segmented text control rather than an icon because
/// DESIGN.md already uses that idiom for the entry sheet's income/expense
/// toggle, and an unlabelled icon would not survive the "no default Material
/// widgets left unstyled" bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import 'period_picker.dart';
import 'package:tally/data/providers.dart';

/// Human label for the currently selected period: `Today` / `Yesterday` /
/// `Tue, Aug 19` in the day lens, `Aug 2026` in the month lens, `1 - 20 Aug`
/// in the range lens.
///
/// [long] spells the month out (`August 2026`) for headings that have a whole
/// line to themselves; the default is the compact form the bar uses, because
/// the bar shares its row with the lens toggle.
String periodLabel(
  BuildContext context, {
  required PeriodMode mode,
  required DateTime start,
  DateRange? range,
  bool long = false,
}) {
  final String locale = context.localeTag;
  switch (mode) {
    case PeriodMode.month:
      return long
          ? monthLabel(start, locale: locale)
          : shortMonthYearLabel(start, locale: locale);
    case PeriodMode.range:
      final DateRange r = range ?? DateRange(start, start);
      return rangeLabel(r.from, r.to, locale: locale);
    case PeriodMode.day:
      final DateTime now = DateTime.now();
      if (isSameDay(start, now)) return context.l10n.commonToday;
      if (isSameDay(start, addDays(dayStart(now), -1))) {
        return context.l10n.commonYesterday;
      }
      return long
          ? dayLabel(start, locale: locale)
          : dayMonthLabel(start, locale: locale);
  }
}

/// The period pill and the lens toggle, on one line.
class PeriodBar extends StatelessWidget {
  const PeriodBar({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        Expanded(child: PeriodSwitcher()),
        SizedBox(width: 8),
        PeriodModeToggle(),
      ],
    );
  }
}

class PeriodSwitcher extends ConsumerStatefulWidget {
  const PeriodSwitcher({super.key});

  @override
  ConsumerState<PeriodSwitcher> createState() => _PeriodSwitcherState();
}

class _PeriodSwitcherState extends ConsumerState<PeriodSwitcher> {
  // +1 when moving forward in time, -1 backwards — drives slide direction.
  int _direction = 1;

  void _shift(int steps) {
    HapticFeedback.selectionClick();
    setState(() => _direction = steps.sign);
    switch (ref.read(periodModeProvider)) {
      case PeriodMode.day:
        final DateTime current = ref.read(selectedDayProvider);
        ref.read(selectedDayProvider.notifier).state = addDays(current, steps);
      case PeriodMode.month:
        final DateTime current = ref.read(selectedMonthProvider);
        ref.read(selectedMonthProvider.notifier).state =
            addMonths(current, steps);
      case PeriodMode.range:
        // Page by the range's own length: the natural "previous 7 days".
        final DateRange current = ref.read(selectedRangeProvider);
        ref
            .read(selectedRangeProvider.notifier)
            .setDateRange(current.shifted(steps));
    }
  }

  Future<void> _openPicker() async {
    HapticFeedback.selectionClick();
    final PeriodMode mode = ref.read(periodModeProvider);
    switch (mode) {
      case PeriodMode.day:
        final DateTime? picked = await showDayPicker(
          context,
          initial: ref.read(selectedDayProvider),
        );
        if (picked == null || !mounted) return;
        setState(() => _direction =
            picked.isAfter(ref.read(selectedDayProvider)) ? 1 : -1);
        ref.read(selectedDayProvider.notifier).state = picked;
      case PeriodMode.month:
        final DateTime? picked = await showMonthPicker(
          context,
          initial: ref.read(selectedMonthProvider),
        );
        if (picked == null || !mounted) return;
        setState(() => _direction =
            picked.isAfter(ref.read(selectedMonthProvider)) ? 1 : -1);
        ref.read(selectedMonthProvider.notifier).state = monthStart(picked);
      case PeriodMode.range:
        final DateRange? picked = await showRangePicker(
          context,
          initial: ref.read(selectedRangeProvider),
        );
        if (picked == null || !mounted) return;
        await ref.read(selectedRangeProvider.notifier).setDateRange(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TallyTokens t = context.tokens;
    final PeriodMode mode = ref.watch(periodModeProvider);
    final DateTime start = ref.watch(selectedPeriodStartProvider);
    final DateRange range = ref.watch(selectedRangeProvider);

    // Never let the user page into the future: there is nothing there yet.
    final DateTime now = DateTime.now();
    final bool canForward = switch (mode) {
      PeriodMode.day => start.isBefore(dayStart(now)),
      PeriodMode.month => start.isBefore(monthStart(now)),
      PeriodMode.range => range.to.isBefore(dayStart(now)),
    };
    final String key = switch (mode) {
      PeriodMode.day => dayKey(start),
      PeriodMode.month => monthKey(start),
      PeriodMode.range => '${dayKey(range.from)}_${dayKey(range.to)}',
    };

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: <Widget>[
          _Chevron(icon: Icons.chevron_left_rounded, onTap: () => _shift(-1)),
          Expanded(
            child: Semantics(
              button: true,
              label: context.l10n.periodPickDateHint,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _openPicker,
                  child: ClipRect(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                        final Animation<Offset> slide = Tween<Offset>(
                          begin: Offset(0.35 * _direction, 0),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child:
                              SlideTransition(position: slide, child: child),
                        );
                      },
                      child: Row(
                        key: ValueKey<String>('${mode.name}:$key'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                periodLabel(
                                  context,
                                  mode: mode,
                                  start: start,
                                  range: range,
                                ),
                                maxLines: 1,
                                softWrap: false,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall!
                                    .copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.expand_more_rounded,
                            size: 16,
                            color: t.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _Chevron(
            icon: Icons.chevron_right_rounded,
            onTap: canForward ? () => _shift(1) : null,
          ),
        ],
      ),
    );
  }
}

/// The `Day · Month · Range` lens toggle. Small and quiet by design: it shares
/// a line with the period pill and must never compete with the hero number
/// above it.
class PeriodModeToggle extends ConsumerWidget {
  const PeriodModeToggle({super.key});

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    PeriodMode mode,
  ) async {
    HapticFeedback.selectionClick();
    await ref.read(periodModeProvider.notifier).setMode(mode);
    // Entering the range lens with nothing chosen would show whatever span was
    // last stored, which is rarely what the tap meant — ask straight away.
    if (mode == PeriodMode.range && context.mounted) {
      final DateRange? picked = await showRangePicker(
        context,
        initial: ref.read(selectedRangeProvider),
      );
      if (picked != null) {
        await ref.read(selectedRangeProvider.notifier).setDateRange(picked);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TallyTokens t = context.tokens;
    final AppLocalizations l10n = context.l10n;
    final PeriodMode mode = ref.watch(periodModeProvider);

    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ModeSegment(
            label: l10n.periodDay,
            semanticLabel: l10n.periodSwitchToDay,
            selected: mode == PeriodMode.day,
            onTap: () => _select(context, ref, PeriodMode.day),
          ),
          _ModeSegment(
            label: l10n.periodMonth,
            semanticLabel: l10n.periodSwitchToMonth,
            selected: mode == PeriodMode.month,
            onTap: () => _select(context, ref, PeriodMode.month),
          ),
          _ModeSegment(
            label: l10n.periodRange,
            semanticLabel: l10n.periodSwitchToRange,
            selected: mode == PeriodMode.range,
            // Re-tapping the active range segment reopens the picker, which is
            // the only way back to it once a range is set.
            onTap: () => _select(context, ref, PeriodMode.range),
            alwaysTappable: true,
          ),
        ],
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
    this.alwaysTappable = false,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;
  final bool alwaysTappable;

  @override
  Widget build(BuildContext context) {
    final TallyTokens t = context.tokens;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? t.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: selected && !alwaysTappable ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium!.copyWith(
                        color: selected ? t.onAccent : t.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TallyTokens t = context.tokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 36,
          height: 42,
          child: Icon(
            icon,
            size: 22,
            color: onTap == null
                ? t.textSecondary.withValues(alpha: 0.35)
                : t.textPrimary,
          ),
        ),
      ),
    );
  }
}
