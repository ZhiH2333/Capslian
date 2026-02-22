import 'package:shared_preferences/shared_preferences.dart';

const String _keyToken = 'auth_token';

/// 持久化存储 JWT，供拦截器与登出使用。
class TokenStorage {
  TokenStorage(this._prefs);

  final SharedPreferences _prefs;
  String? _cachedToken;

  String? getToken() {
    _cachedToken ??= _prefs.getString(_keyToken);
    return _cachedToken;
  }

  Future<void> setToken(String token) async {
    _cachedToken = token;
    await _prefs.setString(_keyToken, token);
  }

  Future<void> clearToken() async {
    _cachedToken = null;
    await _prefs.remove(_keyToken);
  }
}
