/// Accounts — total balance hero, one-tap "send to savings" chips, live
/// balances, add/edit/archive, drag-to-reorder, and the account the Telegram
/// bot books to.
///
/// Balances are **derived**, never stored (see `AccountsRepository`), so the
/// numbers here move the instant any transaction changes and there is no
/// running total to fall out of step with the rows.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import '../common/account_chip.dart';
import '../common/adaptive_amount.dart';
import '../common/buttons.dart';
import '../common/cards.dart';
import '../common/count_up_amount.dart';
import '../common/empty_state.dart';
import '../entry/entry_sheet.dart';
import 'account_edit_sheet.dart';
import 'package:tally/data/providers.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final locale = context.localeTag;
    final String currency = ref.watch(currencyProvider).value ?? defaultCurrency;
    final List<AccountBalance> balances =
        ref.watch(accountBalancesProvider).value ?? const <AccountBalance>[];
    final int total = ref.watch(netWorthMinorProvider);
    final String defaultId =
        ref.watch(defaultAccountIdProvider).value ?? defaultAccountId;

    // The accounts the "send to" chips offer: savings and investment pots are
    // what the owner puts money ASIDE into, and the whole point of the feature
    // is that doing so takes one tap rather than a trip through the entry
    // sheet's pickers.
    final List<Account> pots = <Account>[
      for (final AccountBalance b in balances)
        if (b.account.kind == AccountKind.savings ||
            b.account.kind == AccountKind.investment)
          b.account,
    ];

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back_rounded, color: t.textPrimary),
                  ),
                  const SizedBox(width: 4),
                  Text(l10n.accountsTitle, style: theme.titleLarge),
                ],
              ),
            ),
            Expanded(
              child: balances.isEmpty
                  ? EmptyState(
                      emoji: '👛',
                      title: l10n.accountsEmptyTitle,
                      message: l10n.accountsEmptyMessage,
                    )
                  : _AccountList(
                      balances: balances,
                      pots: pots,
                      total: total,
                      currency: currency,
                      locale: locale,
                      defaultId: defaultId,
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: l10n.accountsMoveMoney,
                  icon: Icons.swap_horiz_rounded,
                  onPressed: () =>
                      showEntrySheet(context, initialKind: Kind.transfer),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AccentButton(
                  label: l10n.accountNew,
                  icon: Icons.add_rounded,
                  onPressed: () => showAccountEditSheet(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The scrolling body: hero total, quick-send chips, the reorderable account
/// list, then the bot's default-account picker.
///
/// A [ReorderableListView] has to own its scroll view, so the hero and the
/// footer ride in it as header/footer slivers rather than sitting in a Column
/// around it — otherwise dragging would fight two nested scrollables.
class _AccountList extends ConsumerWidget {
  const _AccountList({
    required this.balances,
    required this.pots,
    required this.total,
    required this.currency,
    required this.locale,
    required this.defaultId,
  });

  final List<AccountBalance> balances;
  final List<Account> pots;
  final int total;
  final String currency;
  final String locale;
  final String defaultId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
            child: _TotalHero(
              total: total,
              currency: currency,
              locale: locale,
              pots: pots,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SectionHeader(l10n.accountsTitle),
          ),
        ),
        SliverReorderableList(
          itemCount: balances.length,
          proxyDecorator: (child, index, animation) => AnimatedBuilder(
            animation: animation,
            builder: (context, _) => Transform.scale(
              scale: 1.02,
              // No Material elevation: DESIGN.md's lifted row scales, it never
              // gains a drop shadow.
              child: Material(color: Colors.transparent, child: child),
            ),
          ),
          // onReorderItem (unlike the deprecated onReorder) already accounts
          // for the dragged row being lifted out, so newIndex needs no
          // correction here.
          onReorderItem: (oldIndex, newIndex) {
            if (oldIndex == newIndex) return;
            final List<String> ids = <String>[
              for (final AccountBalance b in balances) b.account.id,
            ];
            ids.insert(newIndex, ids.removeAt(oldIndex));
            HapticFeedback.mediumImpact();
            ref.read(accountsRepoProvider).reorder(ids);
          },
          itemBuilder: (context, index) {
            final AccountBalance b = balances[index];
            return _AccountRow(
              key: ValueKey<String>(b.account.id),
              balance: b,
              index: index,
              currency: currency,
              locale: locale,
              isDefault: b.account.id == defaultId,
            );
          },
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: _DefaultAccountCard(
              accounts: <Account>[
                for (final AccountBalance b in balances) b.account,
              ],
              defaultId: defaultId,
            ),
          ),
        ),
      ],
    );
  }
}

/// The oversized total across every live account, plus the "send to" chips.
class _TotalHero extends StatelessWidget {
  const _TotalHero({
    required this.total,
    required this.currency,
    required this.locale,
    required this.pots,
  });

  final int total;
  final String currency;
  final String locale;
  final List<Account> pots;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.accountsTotalLabel, style: theme.labelSmall),
        const SizedBox(height: 6),
        CountUpAmount(
          minor: total,
          format: (int minor) => formatMinor(minor, currency, locale: locale),
          // Neutral ink even when negative: a card in debt is a fact about
          // your money, not an error state (DESIGN.md — red is destructive
          // actions only).
          style: theme.displayLarge!.copyWith(color: t.textPrimary),
        ),
        if (pots.isNotEmpty) ...[
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final Account a in pots) ...[
                  _SendToChip(account: a),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One-tap "send to savings": opens the entry sheet already in transfer mode
/// with this account as the destination, so the only thing left to type is
/// the amount.
class _SendToChip extends StatelessWidget {
  const _SendToChip({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final Color color = colorFromHex(account.color);
    final String name =
        context.accountName(id: account.id, name: account.name);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        showEntrySheet(
          context,
          initialKind: Kind.transfer,
          initialToAccountId: account.id,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(account.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              context.l10n.accountSendTo(name: name),
              style: theme.labelMedium!.copyWith(
                fontWeight: FontWeight.w600,
                color: t.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    super.key,
    required this.balance,
    required this.index,
    required this.currency,
    required this.locale,
    required this.isDefault,
  });

  final AccountBalance balance;
  final int index;
  final String currency;
  final String locale;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final Account a = balance.account;
    final Color color = colorFromHex(a.color);
    final String name = context.accountName(id: a.id, name: a.name);
    final String kind = accountKindName(l10n, a.kind);
    // Three of the four seed accounts are named after their own type, so the
    // subtitle would read "Cash / Cash". A line that repeats the line above it
    // is noise, not information.
    final bool showKind = kind != name;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => showAccountEditSheet(context, existing: a),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Center(
                      child:
                          Text(a.emoji, style: const TextStyle(fontSize: 19)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.bodyLarge!
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (isDefault) ...[
                              const SizedBox(width: 6),
                              _Badge(label: l10n.accountDefaultBadge),
                            ],
                          ],
                        ),
                        if (showKind) ...[
                          const SizedBox(height: 2),
                          Text(kind, style: theme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Shrinks, then drops its currency symbol, before it would
                  // ever ellipsize: `15 360…` is not an amount.
                  Flexible(
                    child: AdaptiveAmount(
                      formatMinor(balance.balanceMinor, currency,
                          locale: locale),
                      fallback: formatMinorPlain(balance.balanceMinor, currency,
                          locale: locale),
                      style: money(theme.bodyLarge!)
                          .copyWith(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 10),
                  ReorderableDragStartListener(
                    index: index,
                    child: Icon(Icons.drag_handle_rounded,
                        size: 20, color: t.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall!
            .copyWith(color: t.accent, letterSpacing: 0.4),
      ),
    );
  }
}

/// Which account the Telegram bot books to. Synced deliberately: the bot must
/// never have to ask, because asking would cost the 3-second promise.
class _DefaultAccountCard extends ConsumerWidget {
  const _DefaultAccountCard({required this.accounts, required this.defaultId});

  final List<Account> accounts;
  final String defaultId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    return TallyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.accountsDefaultLabel, style: theme.labelSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final Account a in accounts)
                AccountChip(
                  account: a,
                  selected: a.id == defaultId,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    ref.read(settingsRepoProvider).setDefaultAccountId(a.id);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(l10n.accountsDefaultHelp, style: theme.bodySmall),
        ],
      ),
    );
  }
}
