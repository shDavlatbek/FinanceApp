/// Bottom-nav shell: 4 tabs + centered accent FAB opening the entry sheet.
/// Tab switches fade-through (no hard cuts) via [AnimatedBranchContainer].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import '../common/buttons.dart';
import '../entry/entry_sheet.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      body: shell,
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Pressable(
          pressedScale: 0.9,
          onTap: () {
            HapticFeedback.lightImpact();
            showEntrySheet(context);
          },
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: t.accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: t.accent.withValues(alpha: 0.30),
                  blurRadius: 22,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(Icons.add_rounded, size: 30, color: t.onAccent),
          ),
        ),
      ),
      bottomNavigationBar: _TallyNavBar(
        currentIndex: shell.currentIndex,
        onTap: (index) => shell.goBranch(
          index,
          initialLocation: index == shell.currentIndex,
        ),
      ),
    );
  }
}

// ---- nav bar ------------------------------------------------------------------

class _TallyNavBar extends StatelessWidget {
  const _TallyNavBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _icons = [
    Icons.home_rounded,
    Icons.receipt_long_rounded,
    Icons.donut_small_rounded,
    Icons.settings_rounded,
  ];

  static List<String> _labels(AppLocalizations l10n) => [
        l10n.navHome,
        l10n.navHistory,
        l10n.navStats,
        l10n.navSettings,
      ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _navItem(context, 0),
              _navItem(context, 1),
              const SizedBox(width: 68), // FAB notch
              _navItem(context, 2),
              _navItem(context, 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, int index) {
    final t = context.tokens;
    final icon = _icons[index];
    final label = _labels(context.l10n)[index];
    final active = index == currentIndex;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap(index);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: active ? 1.0 : 0.92,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: Icon(
                icon,
                size: 23,
                color: active ? t.textPrimary : t.textSecondary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium!.copyWith(
                    fontSize: 10.5,
                    color: active ? t.textPrimary : t.textSecondary,
                    fontWeight:
                        active ? FontWeight.w700 : FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: active ? 4 : 0,
              height: 4,
              decoration: BoxDecoration(
                color: t.accent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- fade-through branch container ------------------------------------------------

/// Keeps every branch Navigator alive (state preserved) and fades/scales
/// between them on tab change — the DESIGN.md fade-through, 250 ms.
class AnimatedBranchContainer extends StatelessWidget {
  const AnimatedBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final (index, child) in children.indexed)
          _BranchView(
            key: ValueKey('branch-$index'),
            active: index == currentIndex,
            child: child,
          ),
      ],
    );
  }
}

class _BranchView extends StatefulWidget {
  const _BranchView({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_BranchView> createState() => _BranchViewState();
}

class _BranchViewState extends State<_BranchView> {
  late bool _offstage = !widget.active;

  @override
  void didUpdateWidget(covariant _BranchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && _offstage) {
      setState(() => _offstage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // TickerMode must sit *below* the fade/scale animations: muting the
    // outgoing branch's tickers above them would freeze its own fade-out
    // mid-flight, leaving the old tab painted on top of the new one forever.
    return Offstage(
      offstage: _offstage,
      child: IgnorePointer(
        ignoring: !widget.active,
        child: AnimatedOpacity(
          opacity: widget.active ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          onEnd: () {
            if (!widget.active && mounted) {
              setState(() => _offstage = true);
            }
          },
          child: AnimatedScale(
            scale: widget.active ? 1.0 : 0.97,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: TickerMode(
              enabled: widget.active,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
