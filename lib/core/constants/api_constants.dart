import 'package:flutter/foundation.dart';

/// API 基础地址与路径常量。
class ApiConstants {
  ApiConstants._();

  static const String _baseUrlEnv = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://molian-api.zhih2333.workers.dev',
  );

  static const String _wsBaseUrlEnv = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://localhost:8787',
  );

  /// REST API 基地址。Debug 且未显式设置时默认使用本地 127.0.0.1:8787。
  static String get baseUrl {
    if (kDebugMode && _baseUrlEnv == 'https://molian-api.zhih2333.workers.dev') {
      return 'http://127.0.0.1:8787';
    }
    return _baseUrlEnv;
  }

  /// WebSocket 基地址。Debug 且未显式设置时默认使用本地 127.0.0.1:8787。
  static String get wsBaseUrl {
    if (kDebugMode && _wsBaseUrlEnv == 'ws://localhost:8787') {
      return 'ws://127.0.0.1:8787';
    }
    return _wsBaseUrlEnv;
  }
  static const String authLogin = '/api/auth/login';
  static const String authRegister = '/api/auth/register';
  static const String authMe = '/api/auth/me';
  static const String authRefresh = '/api/auth/refresh';
  static const String usersMe = '/api/users/me';
  static const String posts = '/api/posts';
  static const String users = '/api/users';
  static const String follows = '/api/follows';
  static const String messages = '/api/messages';
  static const String upload = '/api/upload';
  static const String usersMeFollowing = '/api/users/me/following';
  static const String usersMeFollowers = '/api/users/me/followers';
  static const String usersMeFriends = '/api/users/me/friends';
  static const String usersSearch = '/api/users/search';
  static const String friendRequests = '/api/friend-requests';
  static const String feeds = '/api/feeds';
  static const String realms = '/api/realms';
  static const String files = '/api/files';
  static const String notificationsList = '/api/notifications';
  static const String notificationsRead = '/api/notifications/read';
  static const String notificationsSubscribe = '/api/notifications/subscribe';
}
