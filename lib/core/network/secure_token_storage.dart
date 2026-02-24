import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'token_storage.dart';

const String _keyToken = 'auth_token';
const String _keyRefreshToken = 'auth_refresh_token';

/// 使用 FlutterSecureStorage 存储 token，适用于需要加密存储的场景。
/// 在 main 中可通过 override tokenStorageProvider 切换为此实现；
/// 使用前需调用 [loadFromStorage] 以填充缓存（因 SecureStorage 仅支持异步读）。
class SecureTokenStorage extends TokenStorage {
  SecureTokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  String? _cachedToken;
  String? _cachedRefreshToken;

  /// 从安全存储加载 token 到缓存，应在 runApp 前调用以便拦截器能同步读到 token。
  Future<void> loadFromStorage() async {
    _cachedToken = await _storage.read(key: _keyToken);
    _cachedRefreshToken = await _storage.read(key: _keyRefreshToken);
  }

  @override
  String? getToken() => _cachedToken;

  @override
  String? getRefreshToken() => _cachedRefreshToken;

  @override
  Future<void> setToken(String token) async {
    _cachedToken = token;
    await _storage.write(key: _keyToken, value: token);
  }

  @override
  Future<void> setTokens(String token, String? refreshToken) async {
    _cachedToken = token;
    _cachedRefreshToken = refreshToken;
    await _storage.write(key: _keyToken, value: token);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _keyRefreshToken, value: refreshToken);
    } else {
      await _storage.delete(key: _keyRefreshToken);
    }
  }

  @override
  Future<void> clearToken() async {
    _cachedToken = null;
    _cachedRefreshToken = null;
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyRefreshToken);
  }
}
