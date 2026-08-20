/// Period switcher: navigates the selected day or month, and the small
/// segmented `Day · Month` pill that swaps between the two lenses.
///
/// Replaces the month-only switcher on Home and Stats. The pill is a
/// segmented text control rather than an icon button because DESIGN.md
/// already uses that idiom for the entry sheet's income/expense toggle, and
/// an unlabelled icon would not survive the "no default Material widgets left
/// unstyled" bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import 'package:tally/data/providers.dart';

/// Human label for the currently selected period: `Today` / `Yesterday` /
/// `Tue, Aug 19` in the day lens, `August 2026` in the month lens.
String periodLabel(
  BuildContext context, {
  required PeriodMode mode,
  required DateTime start,
}) {
  final locale = context.localeTag;
  if (mode == PeriodMode.month) return monthLabel(start, locale: locale);
  final now = DateTime.now();
  if (isSameDay(start, now)) return context.l10n.commonToday;
  if (isSameDay(start, addDays(dayStart(now), -1))) {
    return context.l10n.commonYesterday;
  }
  return dayLabel(start, locale: locale);
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
        final current = ref.read(selectedDayProvider);
        ref.read(selectedDayProvider.notifier).state = addDays(current, steps);
      case PeriodMode.month:
        final current = ref.read(selectedMonthProvider);
        ref.read(selectedMonthProvider.notifier).state =
            addMonths(current, steps);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mode = ref.watch(periodModeProvider);
    final start = ref.watch(selectedPeriodStartProvider);

    // Never let the user page into the future: there is nothing there yet.
    final now = DateTime.now();
    final canForward = switch (mode) {
      PeriodMode.day => start.isBefore(dayStart(now)),
      PeriodMode.month => start.isBefore(monthStart(now)),
    };
    final key = mode == PeriodMode.day ? dayKey(start) : monthKey(start);

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Chevron(
            icon: Icons.chevron_left_rounded,
            onTap: () => _shift(-1),
          ),
          SizedBox(
            width: 156,
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(
                    begin: Offset(0.35 * _direction, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                child: Text(
                  periodLabel(context, mode: mode, start: start),
                  key: ValueKey('${mode.name}:$key'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall!
                      .copyWith(fontWeight: FontWeight.w700),
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

/// The `Day · Month` lens toggle. Small and quiet by design: it sits under the
/// switcher and must never compete with the hero number above it.
class PeriodModeToggle extends ConsumerWidget {
  const PeriodModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l10n = context.l10n;
    final mode = ref.watch(periodModeProvider);

    return Container(
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeSegment(
            label: l10n.periodDay,
            semanticLabel: l10n.periodSwitchToDay,
            selected: mode == PeriodMode.day,
            onTap: () => ref
                .read(periodModeProvider.notifier)
                .setMode(PeriodMode.day),
          ),
          _ModeSegment(
            label: l10n.periodMonth,
            semanticLabel: l10n.periodSwitchToMonth,
            selected: mode == PeriodMode.month,
            onTap: () => ref
                .read(periodModeProvider.notifier)
                .setMode(PeriodMode.month),
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
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? t.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: selected
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
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
    final t = context.tokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 24,
            color: onTap == null
                ? t.textSecondary.withValues(alpha: 0.35)
                : t.textPrimary,
          ),
        ),
      ),
    );
  }
}
