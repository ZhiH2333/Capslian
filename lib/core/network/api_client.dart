import 'package:dio/dio.dart';

import '../constants/api_constants.dart';

/// 全局 Dio 实例，可注入拦截器（如 Authorization）。
Dio createApiClient({String? token}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: <String, dynamic>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    ),
  );
  return dio;
}
