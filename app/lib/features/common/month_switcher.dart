/// Month switcher pill bound to `selectedMonthProvider`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import 'package:tally/data/providers.dart';

class MonthSwitcher extends ConsumerStatefulWidget {
  const MonthSwitcher({super.key});

  @override
  ConsumerState<MonthSwitcher> createState() => _MonthSwitcherState();
}

class _MonthSwitcherState extends ConsumerState<MonthSwitcher> {
  // +1 when moving forward in time, -1 backwards — drives slide direction.
  int _direction = 1;

  void _shift(int months) {
    HapticFeedback.selectionClick();
    setState(() => _direction = months.sign);
    final current = ref.read(selectedMonthProvider);
    ref.read(selectedMonthProvider.notifier).state =
        addMonths(current, months);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final month = ref.watch(selectedMonthProvider);
    final canForward = month.isBefore(monthStart(DateTime.now()));

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
            width: 148,
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
                  monthLabel(month, locale: context.localeTag),
                  key: ValueKey(monthKey(month)),
                  textAlign: TextAlign.center,
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
