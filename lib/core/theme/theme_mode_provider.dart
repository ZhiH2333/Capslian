import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/storage_providers.dart';

const String _keyThemeMode = 'theme_mode';

ThemeMode _themeModeFromString(String? value) {
  if (value == 'dark') return ThemeMode.dark;
  if (value == 'light') return ThemeMode.light;
  return ThemeMode.system;
}

/// 持久化主题模式：light / dark / system。
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeModeNotifier(prefs);
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._prefs)
    : super(_themeModeFromString(_prefs.getString(_keyThemeMode)));

  final SharedPreferences _prefs;

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final value = mode == ThemeMode.dark
        ? 'dark'
        : mode == ThemeMode.light
        ? 'light'
        : 'system';
    await _prefs.setString(_keyThemeMode, value);
  }
}
