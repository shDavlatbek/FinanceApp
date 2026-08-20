/// Pickers behind the period label: a month grid, and a from-to range picker
/// with presets.
///
/// The day lens uses the platform showDatePicker (already themed, already used
/// by the entry sheet), so only the two cases Material has no widget for live
/// here.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import 'buttons.dart';
import 'cards.dart';
import 'package:tally/data/providers.dart';

/// Earliest date any picker offers. Before Tally existed there is nothing to
/// show, and an unbounded picker scrolls forever.
final DateTime kFirstSelectableDay = DateTime(2015);

/// Picks a single day. Never offers a future day: there is nothing there yet.
Future<DateTime?> showDayPicker(
  BuildContext context, {
  required DateTime initial,
}) async {
  final DateTime today = dayStart(DateTime.now());
  final DateTime start = dayStart(initial);
  final DateTime? result = await showDatePicker(
    context: context,
    initialDate: start.isAfter(today) ? today : start,
    firstDate: kFirstSelectableDay,
    lastDate: today,
  );
  return result == null ? null : dayStart(result);
}

/// Picks a month: a year stepper over a grid of twelve months. Material has no
/// month picker, and opening a full calendar to choose "August" is the wrong
/// shape for the job.
Future<DateTime?> showMonthPicker(
  BuildContext context, {
  required DateTime initial,
}) {
  return showTallySheet<DateTime>(
    context,
    builder: (BuildContext context) => _MonthPickerBody(initial: initial),
  );
}

/// Picks an inclusive from-to day span, with presets for the spans people
/// actually ask for.
Future<DateRange?> showRangePicker(
  BuildContext context, {
  required DateRange initial,
}) {
  return showTallySheet<DateRange>(
    context,
    builder: (BuildContext context) => _RangePickerBody(initial: initial),
  );
}

// ---- month grid --------------------------------------------------------------

class _MonthPickerBody extends StatefulWidget {
  const _MonthPickerBody({required this.initial});

  final DateTime initial;

  @override
  State<_MonthPickerBody> createState() => _MonthPickerBodyState();
}

class _MonthPickerBodyState extends State<_MonthPickerBody> {
  late int _year = widget.initial.year;

  @override
  Widget build(BuildContext context) {
    final TextTheme theme = Theme.of(context).textTheme;
    final AppLocalizations l10n = context.l10n;
    final String locale = context.localeTag;
    final DateTime now = DateTime.now();
    final DateTime selected = monthStart(widget.initial);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l10n.periodPickMonthTitle, style: theme.titleMedium),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              _StepArrow(
                icon: Icons.chevron_left_rounded,
                onTap: _year > kFirstSelectableDay.year
                    ? () => setState(() => _year--)
                    : null,
              ),
              Expanded(
                child: Text(
                  _year.toString(),
                  textAlign: TextAlign.center,
                  style: theme.titleMedium!.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              _StepArrow(
                icon: Icons.chevron_right_rounded,
                onTap: _year < now.year ? () => setState(() => _year++) : null,
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.1,
            children: <Widget>[
              for (int m = 1; m <= 12; m++)
                _GridChip(
                  label: shortMonthLabel(DateTime(_year, m), locale: locale),
                  selected: selected.year == _year && selected.month == m,
                  // A month that has not started yet holds nothing.
                  enabled: !DateTime(_year, m).isAfter(monthStart(now)),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).pop(DateTime(_year, m));
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- range -------------------------------------------------------------------

class _RangePickerBody extends StatefulWidget {
  const _RangePickerBody({required this.initial});

  final DateRange initial;

  @override
  State<_RangePickerBody> createState() => _RangePickerBodyState();
}

class _RangePickerBodyState extends State<_RangePickerBody> {
  late DateTime _from = widget.initial.from;
  late DateTime _to = widget.initial.to;

  Future<void> _pick({required bool isFrom}) async {
    final DateTime? picked = await showDayPicker(
      context,
      initial: isFrom ? _from : _to,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        // Keep the span valid without silently discarding the tap: dragging
        // the start past the end pulls the end along rather than rejecting it.
        if (_from.isAfter(_to)) _to = _from;
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = _to;
      }
    });
  }

  void _preset(DateRange range) {
    HapticFeedback.selectionClick();
    setState(() {
      _from = range.from;
      _to = range.to;
    });
  }

  @override
  Widget build(BuildContext context) {
    final TallyTokens t = context.tokens;
    final TextTheme theme = Theme.of(context).textTheme;
    final AppLocalizations l10n = context.l10n;
    final String locale = context.localeTag;
    final DateTime today = dayStart(DateTime.now());
    final DateRange current = DateRange(_from, _to);

    final List<(String, DateRange)> presets = <(String, DateRange)>[
      (l10n.periodPresetLast7, DateRange.lastDays(7, now: today)),
      (l10n.periodPresetLast30, DateRange.lastDays(30, now: today)),
      (l10n.periodPresetThisMonth, DateRange(monthStart(today), today)),
      (
        l10n.periodPresetLastMonth,
        DateRange(
          addMonths(monthStart(today), -1),
          addDays(monthStart(today), -1),
        )
      ),
      (l10n.periodPresetThisYear, DateRange(DateTime(today.year), today)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l10n.periodPickRangeTitle, style: theme.titleMedium),
          const SizedBox(height: 4),
          Text(
            l10n.periodRangeDays(count: current.dayCount),
            style: theme.bodySmall!.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _DateField(
                  caption: l10n.periodRangeFrom,
                  value: dayMonthLabel(_from, locale: locale),
                  onTap: () => _pick(isFrom: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateField(
                  caption: l10n.periodRangeTo,
                  value: dayMonthLabel(_to, locale: locale),
                  onTap: () => _pick(isFrom: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final (String label, DateRange range) in presets)
                _PresetChip(
                  label: label,
                  selected: range == current,
                  onTap: () => _preset(range),
                ),
            ],
          ),
          const SizedBox(height: 20),
          AccentButton(
            label: l10n.periodApplyRange,
            onPressed: () => Navigator.of(context).pop(current),
          ),
        ],
      ),
    );
  }
}

// ---- parts -------------------------------------------------------------------

class _DateField extends StatelessWidget {
  const _DateField({
    required this.caption,
    required this.value,
    required this.onTap,
  });

  final String caption;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TallyTokens t = context.tokens;
    final TextTheme theme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: t.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                caption,
                style: theme.labelSmall!.copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.titleSmall!.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TallyTokens t = context.tokens;
    final TextTheme theme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? t.accent : t.surfaceRaised,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? t.accent : t.border),
          ),
          child: Text(
            label,
            style: theme.labelMedium!.copyWith(
              color: selected ? t.onAccent : t.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _GridChip extends StatelessWidget {
  const _GridChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TallyTokens t = context.tokens;
    final TextTheme theme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? t.accent : t.surfaceRaised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? t.accent : t.border),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.titleSmall!.copyWith(
              color: !enabled
                  ? t.textSecondary.withValues(alpha: 0.4)
                  : selected
                      ? t.onAccent
                      : t.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _StepArrow extends StatelessWidget {
  const _StepArrow({required this.icon, this.onTap});

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
          width: 40,
          height: 40,
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
