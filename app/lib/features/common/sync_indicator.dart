/// Subtle sync/offline chip — visible only when something is worth saying.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import 'package:tally/data/providers.dart';

class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l10n = context.l10n;
    final status = ref.watch(syncStatusProvider).value;

    (Widget, String)? chip = switch (status) {
      SyncSyncing() => (
          SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
                strokeWidth: 1.8, color: t.accent),
          ),
          l10n.syncIndicatorSyncing
        ),
      SyncOffline() => (
          _dot(const Color(0xFFE8C95A)),
          l10n.syncIndicatorOffline
        ),
      SyncError() => (_dot(t.danger), l10n.syncIndicatorIssue),
      _ => null,
    };

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerRight,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: chip == null
            ? const SizedBox.shrink()
            : GestureDetector(
                key: ValueKey(chip.$2),
                onTap: () => context.go('/settings'),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: t.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      chip.$1,
                      const SizedBox(width: 7),
                      Text(
                        chip.$2,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium!
                            .copyWith(color: t.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
