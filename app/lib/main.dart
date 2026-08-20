/// Tally — local-first personal money tracker.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import 'core/theme.dart';
import 'features/common/app_providers.dart';
import 'features/shell/app_router.dart';
import 'l10n/l10n.dart';
import 'l10n/locale_controller.dart';
import 'package:tally/data/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: TallyApp()));
}

class TallyApp extends ConsumerStatefulWidget {
  const TallyApp({super.key});

  @override
  ConsumerState<TallyApp> createState() => _TallyAppState();
}

class _TallyAppState extends ConsumerState<TallyApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Sync on app start (no-op in standalone mode).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncEngineProvider).syncNow();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncEngineProvider).syncNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    // `routerProvider` deliberately does NOT depend on the locale: rebuilding
    // the GoRouter would reset navigation state on every language switch.
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    // null = follow the device locale ("System" in the picker).
    final locale = ref.watch(appLocaleProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: tallyTheme(Brightness.light),
      darkTheme: tallyTheme(Brightness.dark),
      themeMode: themeMode,
      builder: (context, child) => _IntlDefaultLocaleSync(child: child),
    );
  }
}

/// Keeps `Intl.defaultLocale` pinned to the *resolved* locale.
///
/// Flutter never sets `intl`'s global locale, so any `DateFormat` /
/// `NumberFormat` built without an explicit locale stays `en_US` forever. The
/// app passes the locale explicitly everywhere; this is the second belt, for
/// anything that slips through (including `intl` internals).
class _IntlDefaultLocaleSync extends StatelessWidget {
  const _IntlDefaultLocaleSync({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    // Localizations.localeOf -> the locale AFTER basicLocaleListResolution,
    // which is what "System" must follow.
    intl.Intl.defaultLocale = context.localeTag;
    return child ?? const SizedBox.shrink();
  }
}
