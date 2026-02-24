import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/api_constants.dart';
import 'storage_providers.dart';
import '../../features/auth/providers/auth_providers.dart';

/// 认证相关路径（注册/登录/me），换网络或 IP 后易出现短暂连接失败，需要重试。
const List<String> _authPaths = [
  ApiConstants.authRegister,
  ApiConstants.authLogin,
  ApiConstants.authMe,
];

bool _isAuthPath(String path) {
  return _authPaths.any((p) => path.startsWith(p) || path.endsWith(p));
}

/// 对认证请求在连接/超时类错误时重试一次，缓解换 IP 或网络切换后的短暂失败。
class _AuthRetryInterceptor extends Interceptor {
  _AuthRetryInterceptor(this._dio);

  final Dio _dio;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final opts = err.requestOptions;
    final shouldRetry =
        _isAuthPath(opts.path) &&
        opts.extra['auth_retry'] != true &&
        (err.type == DioExceptionType.connectionTimeout ||
            err.type == DioExceptionType.sendTimeout ||
            err.type == DioExceptionType.receiveTimeout ||
            err.type == DioExceptionType.connectionError);
    if (!shouldRetry) {
      return handler.next(err);
    }
    opts.extra['auth_retry'] = true;
    _dio.fetch(opts).then(handler.resolve).catchError((Object e) {
      handler.next(err);
    });
  }
}

/// 401 时尝试 refresh，成功则重试原请求，失败则清 token 并置空登录状态。
class _Auth401Interceptor extends Interceptor {
  _Auth401Interceptor(this._ref);

  final Ref _ref;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }
    final path = err.requestOptions.path;
    if (path.contains('auth/refresh') || path.endsWith('auth/refresh')) {
      return handler.next(err);
    }
    final tokenStorage = _ref.read(tokenStorageProvider);
    final refreshToken = tokenStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      _clearAuthAndReject(handler, err);
      return;
    }
    final rawDio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: <String, dynamic>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    rawDio
        .post<Map<String, dynamic>>(
          ApiConstants.authRefresh,
          data: <String, dynamic>{'refresh_token': refreshToken},
        )
        .then((Response<Map<String, dynamic>> res) {
          if (res.statusCode == 200 &&
              res.data != null &&
              res.data!['token'] != null &&
              res.data!['user'] != null) {
            final token = res.data!['token'] as String;
            final newRefresh = res.data!['refresh_token'] as String?;
            tokenStorage.setTokens(token, newRefresh);
            final opts = err.requestOptions;
            opts.headers['Authorization'] = 'Bearer $token';
            final dio = _ref.read(dioProvider);
            dio.fetch(opts).then(handler.resolve).catchError((Object e) {
              handler.next(err);
            });
          } else {
            _clearAuthAndReject(handler, err);
          }
        })
        .catchError((Object _) {
          _clearAuthAndReject(handler, err);
        });
  }

  void _clearAuthAndReject(ErrorInterceptorHandler handler, DioException err) {
    _ref.read(tokenStorageProvider).clearToken();
    _ref.read(authStateProvider.notifier).logout();
    handler.next(err);
  }
}

/// 提供带 Authorization、401 刷新重试与认证重试的 Dio 实例。
final dioProvider = Provider<Dio>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: <String, dynamic>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );
  dio.interceptors.add(_AuthRetryInterceptor(dio));
  dio.interceptors.add(_Auth401Interceptor(ref));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        final token = tokenStorage.getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ),
  );
  return dio;
});
