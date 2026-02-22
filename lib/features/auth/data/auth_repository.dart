import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/token_storage.dart';
import '../data/models/user_model.dart';

/// 认证接口：注册、登录、获取当前用户、登出。
class AuthRepository {
  AuthRepository({
    required Dio dio,
    required TokenStorage tokenStorage,
  })  : _dio = dio,
        _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  Future<UserModel> register({
    required String username,
    required String password,
    String? displayName,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConstants.authRegister,
        data: <String, dynamic>{
          'username': username,
          'password': password,
          if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
        },
      );
      final data = response.data;
      if (data == null || data['user'] == null) throw Exception('注册响应异常');
      final token = data['token'] as String?;
      if (token != null && token.isNotEmpty) await _tokenStorage.setToken(token);
      return UserModel.fromJson(data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response!.data as Map)['error'] as String? : null;
      throw Exception(msg ?? e.message ?? '注册失败');
    }
  }

  Future<UserModel> login({required String username, required String password}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConstants.authLogin,
        data: <String, dynamic>{'username': username, 'password': password},
      );
      final data = response.data;
      if (data == null || data['user'] == null) throw Exception('登录响应异常');
      final token = data['token'] as String?;
      if (token != null && token.isNotEmpty) await _tokenStorage.setToken(token);
      return UserModel.fromJson(data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response!.data as Map)['error'] as String? : null;
      throw Exception(msg ?? e.message ?? '登录失败');
    }
  }

  Future<UserModel?> getMe() async {
    final token = _tokenStorage.getToken();
    if (token == null || token.isEmpty) return null;
    try {
      final response = await _dio.get<Map<String, dynamic>>(ApiConstants.authMe);
      final data = response.data;
      if (data == null || data['user'] == null) return null;
      return UserModel.fromJson(data['user'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    await _tokenStorage.clearToken();
  }
}
