import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/storage_providers.dart';
import 'theme_settings.dart';

const String _keyCardTransparency = 'theme_card_transparency';
const String _keyAppBarTransparent = 'theme_app_bar_transparent';
const String _keyCustomFonts = 'theme_custom_fonts';
const String _keyShowBackgroundImage = 'theme_show_background_image';

/// 主题可配置项持久化。
final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsNotifier, ThemeSettings>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeSettingsNotifier(prefs);
});

class ThemeSettingsNotifier extends StateNotifier<ThemeSettings> {
  ThemeSettingsNotifier(SharedPreferences prefs) : _prefs = prefs, super(_load(prefs));

  static ThemeSettings _load(SharedPreferences prefs) {
    return ThemeSettings(
      cardTransparency: prefs.getDouble(_keyCardTransparency) ?? 1.0,
      appBarTransparent: prefs.getBool(_keyAppBarTransparent) ?? false,
      customFonts: prefs.getString(_keyCustomFonts),
      showBackgroundImage: prefs.getBool(_keyShowBackgroundImage) ?? false,
    );
  }

  final SharedPreferences _prefs;

  Future<void> setCardTransparency(double value) async {
    state = state.copyWith(cardTransparency: value.clamp(0.0, 1.0));
    await _prefs.setDouble(_keyCardTransparency, state.cardTransparency);
  }

  Future<void> setAppBarTransparent(bool value) async {
    state = state.copyWith(appBarTransparent: value);
    await _prefs.setBool(_keyAppBarTransparent, value);
  }

  Future<void> setCustomFonts(String? value) async {
    state = state.copyWith(customFonts: value);
    if (value == null) {
      await _prefs.remove(_keyCustomFonts);
    } else {
      await _prefs.setString(_keyCustomFonts, value);
    }
  }

  Future<void> setShowBackgroundImage(bool value) async {
    state = state.copyWith(showBackgroundImage: value);
    await _prefs.setBool(_keyShowBackgroundImage, value);
  }

  Future<void> update(ThemeSettings settings) async {
    state = settings;
    await _prefs.setDouble(_keyCardTransparency, state.cardTransparency);
    await _prefs.setBool(_keyAppBarTransparent, state.appBarTransparent);
    if (state.customFonts != null) {
      await _prefs.setString(_keyCustomFonts, state.customFonts!);
    } else {
      await _prefs.remove(_keyCustomFonts);
    }
    await _prefs.setBool(_keyShowBackgroundImage, state.showBackgroundImage);
  }
}
