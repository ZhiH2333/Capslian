import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import 'models/notification_model.dart';

/// 通知列表分页结果。
class NotificationsPageResult {
  const NotificationsPageResult({
    required this.notifications,
    this.nextCursor,
  });
  final List<NotificationModel> notifications;
  final String? nextCursor;
}

/// 通知与推送订阅接口。
class NotificationsRepository {
  NotificationsRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// 获取当前用户通知列表（分页）。
  Future<NotificationsPageResult> fetchNotifications({
    int limit = 20,
    String? cursor,
  }) async {
    final query = <String, String>{'limit': limit.toString()};
    if (cursor != null && cursor.isNotEmpty) query['cursor'] = cursor;
    final uri = Uri.parse(ApiConstants.notificationsList).replace(queryParameters: query);
    final response = await _dio.get<Map<String, dynamic>>(uri.toString());
    final data = response.data;
    if (data == null || data['notifications'] is! List) {
      return const NotificationsPageResult(notifications: []);
    }
    final list = (data['notifications'] as List)
        .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final nextCursor = data['nextCursor'] as String?;
    return NotificationsPageResult(notifications: list, nextCursor: nextCursor);
  }

  /// 标记通知已读（单条、多条或全部）。
  Future<void> markRead({String? id, List<String>? ids}) async {
    final Map<String, dynamic> body = <String, dynamic>{};
    if (id != null) body['id'] = id;
    if (ids != null && ids.isNotEmpty) body['ids'] = ids;
    await _dio.post<Map<String, dynamic>>(
      ApiConstants.notificationsRead,
      data: body,
    );
  }

  /// 将 FCM token 上报到后端，用于推送。
  Future<void> subscribeFcm(String fcmToken) async {
    await _dio.post<Map<String, dynamic>>(
      ApiConstants.notificationsSubscribe,
      data: <String, dynamic>{'fcm_token': fcmToken},
    );
  }
}
