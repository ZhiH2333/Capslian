import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/notifications_repository.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return NotificationsRepository(dio: dio);
});

/// 通知列表（分页）；用于通知中心页。
final notificationsListProvider = FutureProvider.family<NotificationsPageResult, NotificationsListKey>((ref, key) async {
  final repo = ref.watch(notificationsRepositoryProvider);
  return repo.fetchNotifications(limit: key.limit, cursor: key.cursor);
});

class NotificationsListKey {
  const NotificationsListKey({this.limit = 20, this.cursor});
  final int limit;
  final String? cursor;
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NotificationsListKey && limit == other.limit && cursor == other.cursor;
  @override
  int get hashCode => Object.hash(limit, cursor);
}

/// 登录成功后尝试获取 FCM token 并上报到 CF；未配置 Firebase 时静默忽略。
final pushSubscribeOnAuthProvider = Provider<void>((ref) {
  ref.listen(authStateProvider, (Object? prev, AsyncValue<dynamic> next) {
    next.whenData((dynamic user) {
      if (user == null) return;
      _subscribeFcmIfAvailable(ref);
    });
  });
});

Future<void> _subscribeFcmIfAvailable(Ref ref) async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    final repo = ref.read(notificationsRepositoryProvider);
    await repo.subscribeFcm(token);
  } catch (_) {
    // Firebase 未配置或权限未授予时忽略
  }
}
