import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'token_storage.dart';

/// 须在 main 中先初始化 SharedPreferences 并通过 overrides 注入。
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw StateError('请在 main() 中初始化 SharedPreferences 并 override sharedPreferencesProvider');
});

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PrefsTokenStorage(prefs);
});
