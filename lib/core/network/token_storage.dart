import 'package:shared_preferences/shared_preferences.dart';

/// Token 存储抽象，供拦截器与登出使用；可实现为 SharedPreferences 或 FlutterSecureStorage。
abstract class TokenStorage {
  String? getToken();
  String? getRefreshToken();
  Future<void> setToken(String token);
  Future<void> setTokens(String token, String? refreshToken);
  Future<void> clearToken();
}

const String _keyToken = 'auth_token';
const String _keyRefreshToken = 'auth_refresh_token';

/// 使用 SharedPreferences 的 Token 存储（默认实现）。
class PrefsTokenStorage extends TokenStorage {
  PrefsTokenStorage(this._prefs);

  final SharedPreferences _prefs;
  String? _cachedToken;
  String? _cachedRefreshToken;

  @override
  String? getToken() {
    _cachedToken ??= _prefs.getString(_keyToken);
    return _cachedToken;
  }

  @override
  String? getRefreshToken() {
    _cachedRefreshToken ??= _prefs.getString(_keyRefreshToken);
    return _cachedRefreshToken;
  }

  @override
  Future<void> setToken(String token) async {
    _cachedToken = token;
    await _prefs.setString(_keyToken, token);
  }

  @override
  Future<void> setTokens(String token, String? refreshToken) async {
    _cachedToken = token;
    _cachedRefreshToken = refreshToken;
    await _prefs.setString(_keyToken, token);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _prefs.setString(_keyRefreshToken, refreshToken);
    } else {
      await _prefs.remove(_keyRefreshToken);
    }
  }

  @override
  Future<void> clearToken() async {
    _cachedToken = null;
    _cachedRefreshToken = null;
    await _prefs.remove(_keyToken);
    await _prefs.remove(_keyRefreshToken);
  }
}
