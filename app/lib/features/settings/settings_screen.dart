/// Settings — Google Drive connection (OAuth device flow), live sync status +
/// last-synced, manual sync, currency picker, appearance, categories and
/// accounts links, file export/import, standalone-mode notice, about.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import '../../l10n/locale_controller.dart';
import '../common/app_providers.dart';
import '../common/buttons.dart';
import '../common/cards.dart';
import '../common/format.dart';
import 'package:tally/data/providers.dart';

/// ISO-4217 codes offered by the currency picker. Names are looked up in the
/// ARB catalogs via [currencyName].
const List<String> kCommonCurrencies = [
  'USD',
  'EUR',
  'RUB',
  'UZS',
  'KZT',
  'GBP',
  'UAH',
  'PLN',
  'CZK',
  'CHF',
  'SEK',
  'NOK',
  'DKK',
  'JPY',
  'CNY',
  'INR',
  'CAD',
  'AUD',
  'NZD',
  'BRL',
  'MXN',
  'TRY',
  'KRW',
  'SGD',
  'HKD',
  'ILS',
  'AED',
  'ZAR',
];

/// The language options in the picker: `''` = follow the device locale, then
/// one entry per shipped locale. Endonyms are never translated.
const List<String> kLanguageOptions = ['', 'en', 'ru', 'uz'];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

/// Where the Google Drive device-authorization flow currently is.
enum _AuthPhase { idle, requesting, waiting, failed }

/// Which file operation is in flight, so exactly one row shows a spinner and
/// a second tap cannot start a concurrent one.
enum _BackupAction { exportJson, exportCsv, import }

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _AuthPhase _phase = _AuthPhase.idle;
  DeviceAuthPrompt? _prompt;
  String? _authError;
  int _pollAttempt = 0;
  bool _manualSyncing = false;
  bool _disconnecting = false;
  _BackupAction? _backupBusy;

  // ---- export / import ----------------------------------------------------

  /// Writes a file through the transport and reports what happened.
  ///
  /// Cancelling the platform dialog is a normal outcome and says so; anything
  /// thrown is surfaced with its message rather than swallowed, because a
  /// backup the owner believes exists and does not is the worst failure this
  /// screen can have.
  Future<void> _write(
    _BackupAction action,
    Future<BackupFile> Function() build,
  ) async {
    if (_backupBusy != null) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final transport = ref.read(backupTransportProvider);
    setState(() => _backupBusy = action);
    try {
      final BackupFile file = await build();
      final bool saved = await transport.save(file);
      messenger.showSnackBar(SnackBar(
        content: Text(saved
            ? l10n.backupSavedSnack(file: file.fileName)
            : l10n.backupCancelledSnack),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.backupFailedSnack(message: e.toString())),
      ));
    } finally {
      if (mounted) setState(() => _backupBusy = null);
    }
  }

  Future<void> _exportSnapshot() => _write(
        _BackupAction.exportJson,
        () => ref.read(backupServiceProvider).buildSnapshotBackup(),
      );

  Future<void> _exportCsv() {
    // Only the NAMING is resolved here, where there is a BuildContext and a
    // locale; the service loads the rows itself. Passing a lookup map read off
    // `categoriesByIdProvider` was the first attempt and it exported empty
    // name columns: that provider is derived from a stream this screen does
    // not subscribe to, so reading it cold yields an empty map.
    final l10n = context.l10n;
    final String currency = ref.read(currencyProvider).value ?? defaultCurrency;
    return _write(
      _BackupAction.exportCsv,
      () => ref.read(backupServiceProvider).buildCsvExport(
            currency: currency,
            localizeCategory: (String id, String name) =>
                localizedCategoryName(l10n, id: id, name: name),
            localizeAccount: (String id, String name) =>
                localizedAccountName(l10n, id: id, name: name),
          ),
    );
  }

  Future<void> _importSnapshot() async {
    if (_backupBusy != null) return;
    final l10n = context.l10n;
    final t = context.tokens;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.backupImportConfirmTitle),
        content: Text(l10n.backupImportConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: t.accent),
            child: Text(l10n.backupImportConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final transport = ref.read(backupTransportProvider);
    final service = ref.read(backupServiceProvider);
    setState(() => _backupBusy = _BackupAction.import);
    try {
      final PickedBackupFile? picked = await transport.pick();
      if (picked == null) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.backupCancelledSnack)),
        );
        return;
      }
      final SnapshotMergeResult result =
          await service.importSnapshot(picked.bytes);
      messenger.showSnackBar(
        SnackBar(content: Text(_importSummary(l10n, result))),
      );
    } on BackupImportException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.backupImportFailedSnack(message: e.message)),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.backupImportFailedSnack(message: e.toString())),
      ));
    } finally {
      if (mounted) setState(() => _backupBusy = null);
    }
  }

  /// What the import actually did. "Nothing" is a real, correct answer — it is
  /// what importing the same file twice reports — so it gets its own sentence
  /// rather than a bare "0 rows".
  String _importSummary(AppLocalizations l10n, SnapshotMergeResult result) {
    final StringBuffer out = StringBuffer();
    if (result.isEmpty) {
      out.write(l10n.backupImportNothingSnack);
    } else {
      out.write(l10n.backupImportedSnack(count: result.rows));
    }
    if (result.skipped.isNotEmpty) {
      out.write(' · ');
      out.write(l10n.backupImportSkippedSnack(count: result.skipped.length));
    }
    return out.toString();
  }

  // ---- Google Drive device flow ------------------------------------------

  Future<void> _connectDrive() async {
    final engine = ref.read(syncEngineProvider);
    final l10n = context.l10n;
    HapticFeedback.selectionClick();
    setState(() {
      _phase = _AuthPhase.requesting;
      _authError = null;
      _prompt = null;
      _pollAttempt = 0;
    });
    try {
      final prompt = await engine.beginAuthorization();
      if (!mounted) return;
      setState(() {
        _prompt = prompt;
        _phase = _AuthPhase.waiting;
      });
      await engine.completeAuthorization(
        prompt,
        onAttempt: (attempt) {
          if (mounted) setState(() => _pollAttempt = attempt);
        },
      );
      if (!mounted) return;
      setState(() {
        _phase = _AuthPhase.idle;
        _prompt = null;
      });
      ref.invalidate(driveConnectionProvider);
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.driveConnectedSnack)),
      );
    } on DeviceAuthException catch (e) {
      if (!mounted) return;
      if (e.code == DeviceAuthException.cancelled) {
        setState(() {
          _phase = _AuthPhase.idle;
          _prompt = null;
        });
        return;
      }
      setState(() {
        _phase = _AuthPhase.failed;
        _prompt = null;
        _authError = _authMessage(l10n, e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _AuthPhase.failed;
        _prompt = null;
        _authError = e.toString();
      });
    }
  }

  String _authMessage(AppLocalizations l10n, DeviceAuthException e) =>
      switch (e.code) {
        DeviceAuthException.notAvailable => l10n.authErrorNoClient,
        DeviceAuthException.denied => l10n.authErrorDenied,
        DeviceAuthException.expired => l10n.authErrorExpired,
        'network' => l10n.authErrorNetwork,
        _ => e.message,
      };

  void _cancelConnect() {
    ref.read(syncEngineProvider).cancelAuthorization();
    setState(() {
      _phase = _AuthPhase.idle;
      _prompt = null;
    });
  }

  Future<void> _copyCode() async {
    final code = _prompt?.userCode;
    if (code == null) return;
    final l10n = context.l10n;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.driveCodeCopied)),
    );
  }

  Future<void> _openVerificationUrl() async {
    final url = _prompt?.verificationUrl;
    if (url == null) return;
    final l10n = context.l10n;
    HapticFeedback.selectionClick();
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.driveLinkCopied)),
      );
    }
  }

  Future<void> _disconnect() async {
    final l10n = context.l10n;
    setState(() => _disconnecting = true);
    await ref.read(syncEngineProvider).disconnect();
    if (!mounted) return;
    setState(() {
      _disconnecting = false;
      _phase = _AuthPhase.idle;
      _prompt = null;
      _authError = null;
    });
    ref.invalidate(driveConnectionProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.driveDisconnectedSnack)),
    );
  }

  Future<void> _syncNow() async {
    final l10n = context.l10n;
    final engine = ref.read(syncEngineProvider);
    setState(() => _manualSyncing = true);
    // A pass triggered 3 s after the last local write (or by `resumed`) may
    // already be in flight; syncNow() then awaits that run instead of
    // reporting a failure. The snackbar is picked from the status the pass
    // actually left behind, so it can never contradict the status row above.
    await engine.syncNow();
    if (!mounted) return;
    setState(() => _manualSyncing = false);
    ref.invalidate(driveConnectionProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_syncOutcomeLabel(l10n, engine.status))),
    );
  }

  /// Snackbar text for the status a manual sync ended on.
  String _syncOutcomeLabel(AppLocalizations l10n, SyncStatus status) =>
      switch (status) {
        SyncIdle() => l10n.syncedSnack,
        SyncOffline() => l10n.syncStatusOffline,
        // Another trigger (a write during our pass) started a fresh one.
        SyncSyncing() => l10n.syncStatusSyncing,
        _ => l10n.syncFailedSnack,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final locale = context.localeTag;
    final status = ref.watch(syncStatusProvider).value;
    final lastSync = ref.watch(lastSyncMsProvider).value;
    final currency = ref.watch(currencyProvider).value ?? defaultCurrency;
    final themeMode = ref.watch(themeModeProvider);
    final language = ref.watch(localeControllerProvider);
    final configured = status != null && status is! SyncNotConfigured;
    // The refresh token is dead: every pass will keep failing the same way,
    // so the connect button has to be reachable without guessing that
    // Disconnect must be pressed first.
    final needsReconnect = status is SyncError &&
        (status.code == SyncErrorCode.authRevoked ||
            status.code == SyncErrorCode.authExpired);

    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
        children: [
          Text(l10n.settingsTitle, style: theme.titleLarge),
          const SizedBox(height: 20),

          // ---- sync ---------------------------------------------------
          SectionHeader(l10n.settingsSyncSection),
          TallyCard(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusRow(status: status, lastSyncMs: lastSync),
                  if (!configured && _phase == _AuthPhase.idle) ...[
                    const SizedBox(height: 14),
                    _NoticeBox(
                      emoji: '🏝️',
                      text: l10n.driveStandaloneNotice,
                    ),
                    if (!ref.read(syncEngineProvider).canAuthorize) ...[
                      const SizedBox(height: 10),
                      _NoticeBox(
                        emoji: '🔑',
                        text: l10n.driveNoClientNotice,
                      ),
                    ],
                  ],
                  if (configured) ...[
                    const SizedBox(height: 14),
                    _ConnectionSummary(
                        connection: ref.watch(driveConnectionProvider).value),
                  ],
                  if (_phase == _AuthPhase.waiting && _prompt != null) ...[
                    const SizedBox(height: 14),
                    _DeviceCodePanel(
                      prompt: _prompt!,
                      pollAttempt: _pollAttempt,
                      onCopyCode: _copyCode,
                      onOpenUrl: _openVerificationUrl,
                      onCancel: _cancelConnect,
                    ),
                  ],
                  if (_phase == _AuthPhase.failed && _authError != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            size: 15, color: t.danger),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _authError!,
                            style:
                                theme.bodySmall!.copyWith(color: t.danger),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_phase != _AuthPhase.waiting) ...[
                    const SizedBox(height: 14),
                    if (!configured)
                      AccentButton(
                        label: _phase == _AuthPhase.failed
                            ? l10n.commonTryAgain
                            : l10n.driveConnectButton,
                        icon: Icons.cloud_outlined,
                        height: 50,
                        busy: _phase == _AuthPhase.requesting,
                        onPressed: _connectDrive,
                      )
                    else if (needsReconnect)
                      // Authorization is gone: re-authorizing is the only
                      // useful action, so it takes "Sync now"'s place.
                      Row(
                        children: [
                          Expanded(
                            child: AccentButton(
                              label: _phase == _AuthPhase.failed
                                  ? l10n.commonTryAgain
                                  : l10n.driveReconnectButton,
                              icon: Icons.cloud_sync_outlined,
                              height: 48,
                              busy: _phase == _AuthPhase.requesting,
                              onPressed: _connectDrive,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GhostButton(
                              label: l10n.driveDisconnectButton,
                              destructive: true,
                              busy: _disconnecting,
                              onPressed: _disconnect,
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: GhostButton(
                              label: l10n.syncNowButton,
                              icon: Icons.sync_rounded,
                              busy: _manualSyncing,
                              onPressed: _syncNow,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GhostButton(
                              label: l10n.driveDisconnectButton,
                              destructive: true,
                              busy: _disconnecting,
                              onPressed: _disconnect,
                            ),
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ---- preferences -------------------------------------------
          SectionHeader(l10n.settingsPreferencesSection),
          TallyCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              children: [
                _SettingsRowTile(
                  icon: Icons.payments_outlined,
                  title: l10n.settingsCurrency,
                  value: '$currency · '
                      '${currencySymbolFor(currency, locale: locale)}',
                  onTap: () => _pickCurrency(context, currency),
                ),
                Divider(color: t.border, indent: 54),
                _SettingsRowTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: l10n.accountsTitle,
                  value: l10n.settingsAccountsValue,
                  onTap: () => context.push('/accounts'),
                ),
                Divider(color: t.border, indent: 54),
                _SettingsRowTile(
                  icon: Icons.category_outlined,
                  title: l10n.categoriesTitle,
                  value: l10n.settingsCategoriesValue,
                  onTap: () => context.push('/categories'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TallyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.settingsAppearanceLabel, style: theme.labelSmall),
                const SizedBox(height: 12),
                _SegmentedGrid<ThemeMode>(
                  value: themeMode,
                  options: [
                    (
                      ThemeMode.dark,
                      l10n.settingsThemeDark,
                      Icons.dark_mode_outlined
                    ),
                    (
                      ThemeMode.light,
                      l10n.settingsThemeLight,
                      Icons.light_mode_outlined
                    ),
                    (
                      ThemeMode.system,
                      l10n.settingsThemeSystem,
                      Icons.brightness_auto_outlined
                    ),
                  ],
                  onSelect: (mode) =>
                      ref.read(themeModeProvider.notifier).setMode(mode),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TallyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.settingsLanguageLabel, style: theme.labelSmall),
                const SizedBox(height: 12),
                // Language names are endonyms and stay untranslated — you
                // must be able to find your own language in any UI language.
                _SegmentedGrid<String>(
                  value: language,
                  perRow: 2,
                  options: [
                    for (final code in kLanguageOptions)
                      (
                        code,
                        code.isEmpty
                            ? l10n.settingsLanguageSystem
                            : kLanguageEndonyms[code]!,
                        code.isEmpty ? Icons.translate_rounded : null,
                      ),
                  ],
                  onSelect: (code) => ref
                      .read(localeControllerProvider.notifier)
                      .setLanguage(code),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ---- backup --------------------------------------------------
          SectionHeader(l10n.settingsBackupSection),
          TallyCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              children: [
                _SettingsRowTile(
                  icon: Icons.download_outlined,
                  title: l10n.backupExportJsonTitle,
                  value: l10n.backupExportJsonSubtitle,
                  busy: _backupBusy == _BackupAction.exportJson,
                  onTap: _exportSnapshot,
                ),
                Divider(color: t.border, indent: 54),
                _SettingsRowTile(
                  icon: Icons.table_chart_outlined,
                  title: l10n.backupExportCsvTitle,
                  value: l10n.backupExportCsvSubtitle,
                  busy: _backupBusy == _BackupAction.exportCsv,
                  onTap: _exportCsv,
                ),
                Divider(color: t.border, indent: 54),
                _SettingsRowTile(
                  icon: Icons.upload_outlined,
                  title: l10n.backupImportTitle,
                  value: l10n.backupImportSubtitle,
                  busy: _backupBusy == _BackupAction.import,
                  onTap: _importSnapshot,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _NoticeBox(emoji: '📄', text: l10n.backupCsvNotice),
          const SizedBox(height: 24),

          // ---- about ---------------------------------------------------
          SectionHeader(l10n.settingsAboutSection),
          TallyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: t.accent,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Center(
                        child: Text(
                          'T',
                          style: theme.titleLarge!
                              .copyWith(color: t.onAccent, fontSize: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.appTitle,
                            style: theme.titleMedium!
                                .copyWith(fontWeight: FontWeight.w800)),
                        Text(l10n.settingsVersion(version: _appVersion),
                            style: theme.bodySmall),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(l10n.settingsAboutBody, style: theme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _pickCurrency(BuildContext context, String current) {
    showTallySheet<void>(
      context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext).textTheme;
        final t = sheetContext.tokens;
        final l10n = sheetContext.l10n;
        final locale = sheetContext.localeTag;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Text(l10n.settingsCurrency, style: theme.titleMedium),
            ),
            for (final code in kCommonCurrencies)
              ListTile(
                onTap: () {
                  ref.read(settingsRepoProvider).setCurrency(code);
                  Navigator.of(sheetContext).pop();
                },
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: t.surfaceRaised,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.border),
                  ),
                  child: Center(
                    child: Text(
                      currencySymbolFor(code, locale: locale),
                      style: money(theme.bodyMedium!)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                title: Text(code,
                    style: theme.bodyLarge!
                        .copyWith(fontWeight: FontWeight.w700)),
                subtitle:
                    Text(currencyName(l10n, code), style: theme.bodySmall),
                trailing: code == current
                    ? Icon(Icons.check_rounded, color: t.accent)
                    : null,
              ),
          ],
        );
      },
    );
  }
}

/// Version string shown in the About card. Kept next to the picker so the
/// pubspec version and the UI stay in one place.
const String _appVersion = '0.1.0';

/// The Appearance / Language control: equal-width pills with an optional
/// leading icon, an accent-tinted selected state and the 200 ms easeOutCubic
/// transition the rest of the app uses.
///
/// [perRow] wraps onto a second row instead of squeezing four options into
/// one — Russian and Uzbek labels do not survive a quarter of the screen.
class _SegmentedGrid<T> extends StatelessWidget {
  const _SegmentedGrid({
    required this.value,
    required this.options,
    required this.onSelect,
    this.perRow = 3,
  });

  static const double _gap = 8;

  final T value;
  final List<(T, String, IconData?)> options;
  final ValueChanged<T> onSelect;
  final int perRow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            (constraints.maxWidth - _gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final (optionValue, label, icon) in options)
              SizedBox(
                width: width,
                child: _pill(context, optionValue, label, icon),
              ),
          ],
        );
      },
    );
  }

  Widget _pill(
    BuildContext context,
    T optionValue,
    String label,
    IconData? icon,
  ) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final selected = value == optionValue;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onSelect(optionValue);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? t.accent.withValues(alpha: 0.16)
              : t.surfaceRaised,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: selected ? t.accent : t.border),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 15,
                    color: selected ? t.textPrimary : t.textSecondary),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.labelMedium!.copyWith(
                    color: selected ? t.textPrimary : t.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- bits -----------------------------------------------------------------

/// Quiet raised box with an emoji and one paragraph of copy.
class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.emoji, required this.text});

  final String emoji;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.bodySmall)),
        ],
      ),
    );
  }
}

/// Which Drive folder and which device this app publishes as.
class _ConnectionSummary extends StatelessWidget {
  const _ConnectionSummary({required this.connection});

  final DriveConnection? connection;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final c = connection;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.folder_outlined, size: 18, color: t.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c == null
                      ? l10n.driveConnectionTitle
                      : l10n.driveConnectionTitleFolder(
                          folder: c.folderName),
                  style: theme.bodyMedium!
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  c == null
                      ? l10n.driveConnectionUnknownDevice
                      : l10n.driveConnectionDevice(
                          device: c.deviceName,
                          file: c.snapshotFileName,
                        ),
                  style: theme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The live device-flow panel: verification URL, the big copyable user code,
/// and a "waiting for approval" progress line.
class _DeviceCodePanel extends StatelessWidget {
  const _DeviceCodePanel({
    required this.prompt,
    required this.pollAttempt,
    required this.onCopyCode,
    required this.onOpenUrl,
    required this.onCancel,
  });

  final DeviceAuthPrompt prompt;
  final int pollAttempt;
  final VoidCallback onCopyCode;
  final VoidCallback onOpenUrl;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.driveStepOpenLink, style: theme.labelSmall),
          const SizedBox(height: 6),
          Pressable(
            onTap: onOpenUrl,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    prompt.verificationUrl,
                    style: theme.bodyLarge!.copyWith(
                      color: t.accent,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: t.accent,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.open_in_new_rounded, size: 15, color: t.accent),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.driveStepEnterCode, style: theme.labelSmall),
          const SizedBox(height: 8),
          Pressable(
            onTap: onCopyCode,
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    prompt.userCode,
                    style: money(theme.headlineSmall!).copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.copy_rounded, size: 16, color: t.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: t.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  pollAttempt == 0
                      ? l10n.driveWaitingForApproval
                      : l10n.driveWaitingChecked(count: pollAttempt),
                  style: theme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GhostButton(
              label: l10n.commonCancel, height: 44, onPressed: onCancel),
        ],
      ),
    );
  }
}

/// Translates a [SyncError] by its machine-readable code, falling back to the
/// engine's English message for anything unexpected.
String _syncErrorLabel(AppLocalizations l10n, SyncError e) =>
    switch (e.code) {
      SyncErrorCode.authRevoked => l10n.syncErrorAuthRevoked,
      SyncErrorCode.authExpired => l10n.syncErrorAuthExpired,
      SyncErrorCode.driveFull => l10n.syncErrorDriveFull,
      SyncErrorCode.drive => l10n.syncErrorDrive(message: e.message),
      _ => e.message,
    };

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.status, required this.lastSyncMs});

  final SyncStatus? status;
  final int? lastSyncMs;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;

    final (Color color, String label, bool spinning) = switch (status) {
      SyncSyncing() => (t.accent, l10n.syncStatusSyncing, true),
      SyncIdle() => (t.accent, l10n.syncStatusConnected, false),
      SyncOffline() => (
          const Color(0xFFE8C95A),
          l10n.syncStatusOffline,
          false
        ),
      final SyncError e => (t.danger, _syncErrorLabel(l10n, e), false),
      _ => (t.textSecondary, l10n.syncStatusStandalone, false),
    };

    return Row(
      children: [
        if (spinning)
          SizedBox(
            width: 12,
            height: 12,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: color),
          )
        else
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodyLarge!
                      .copyWith(fontWeight: FontWeight.w600)),
              Text(
                lastSyncMs == null
                    ? l10n.syncNeverSynced
                    : l10n.syncLastSynced(
                        time: relativeTime(
                          l10n,
                          lastSyncMs!,
                          locale: context.localeTag,
                        ),
                      ),
                style: theme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsRowTile extends StatelessWidget {
  const _SettingsRowTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  /// Swaps the chevron for a spinner and blocks the tap while a file dialog
  /// or a merge is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: t.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(title,
                    style: theme.bodyLarge!
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
              Flexible(
                child: Text(value,
                    style: theme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right),
              ),
              const SizedBox(width: 6),
              if (busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: t.accent),
                )
              else
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: t.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
