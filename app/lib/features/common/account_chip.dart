/// An account as a selectable pill: emoji, display name, the account's own
/// colour when chosen.
///
/// Shared by the entry sheet's transfer pickers and the Accounts screen's
/// default-account picker, so "which account?" looks and behaves the same
/// wherever it is asked.
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import 'package:tally/data/providers.dart';

class AccountChip extends StatelessWidget {
  const AccountChip({
    super.key,
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final Account account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final Color color = colorFromHex(account.color);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.20) : t.surfaceRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? color : t.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(account.emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Text(
              context.accountName(id: account.id, name: account.name),
              style: theme.labelMedium!.copyWith(
                fontWeight: FontWeight.w600,
                color: selected ? t.textPrimary : t.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled, horizontally scrolling row of [AccountChip]s.
///
/// One line rather than a wrap: the entry sheet stacks a category grid, a
/// note and the date chips below this, and a picker that grows a second row
/// pushes the Save button off a short screen.
class AccountStrip extends StatelessWidget {
  const AccountStrip({
    super.key,
    required this.label,
    required this.accounts,
    required this.selectedId,
    required this.onSelect,
    this.excludeId,
  });

  final String label;
  final List<Account> accounts;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  /// An account to leave out — the other end of a transfer, which cannot also
  /// be this end. Hiding it beats offering a choice that then fails validation.
  final String? excludeId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final List<Account> shown = <Account>[
      for (final Account a in accounts)
        if (a.id != excludeId) a,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, bottom: 6),
          child: Text(label, style: theme.labelSmall),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (final Account a in shown) ...[
                AccountChip(
                  account: a,
                  selected: a.id == selectedId,
                  onTap: () => onSelect(a.id),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
