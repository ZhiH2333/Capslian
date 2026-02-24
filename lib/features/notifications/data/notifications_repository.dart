import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';

/// 通知与推送订阅接口。
class NotificationsRepository {
  NotificationsRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// 将 FCM token 上报到后端，用于推送。
  Future<void> subscribeFcm(String fcmToken) async {
    await _dio.post<Map<String, dynamic>>(
      ApiConstants.notificationsSubscribe,
      data: <String, dynamic>{'fcm_token': fcmToken},
    );
  }
}
