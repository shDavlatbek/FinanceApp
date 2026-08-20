/// UI-level providers that don't belong to the data layer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tally/core/constants.dart';
import 'package:tally/data/providers.dart';

/// Dark by default (DESIGN.md: dark-first); persisted in the local meta table.
final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(ref.watch(databaseProvider)),
);

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._db) : super(ThemeMode.dark) {
    _load();
  }

  final AppDatabase _db;

  Future<void> _load() async {
    final raw = await _db.getMeta(MetaKeys.uiThemeMode);
    if (!mounted) return;
    state = switch (raw) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await _db.setMeta(MetaKeys.uiThemeMode, mode.name);
  }
}
