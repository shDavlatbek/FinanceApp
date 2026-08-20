/// Test helper: pump a widget inside a `Localizations` scope for one locale.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally/core/theme.dart';
import 'package:tally/l10n/l10n.dart';

extension PumpLocalized on WidgetTester {
  /// Wraps [child] in a `MaterialApp` whose locale is pinned to [locale] and
  /// whose delegates are the generated ones (which already bundle the
  /// Material/Cupertino/Widgets globals). The Tally theme is installed too,
  /// because every custom widget reads `context.tokens`.
  Future<void> pumpLocalized(
    Widget child, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.dark,
  }) {
    return pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: tallyTheme(brightness),
        home: Scaffold(body: child),
      ),
    );
  }
}
