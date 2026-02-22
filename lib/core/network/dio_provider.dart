import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/api_constants.dart';
import 'storage_providers.dart';

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

/// 提供带 Authorization 与认证重试的 Dio 实例。
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
