/// API 基础地址与路径常量。
class ApiConstants {
  ApiConstants._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://capslian-api.zhih2333.workers.dev', // 改成这个
  );

  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://localhost:8787',
  );
  static const String authLogin = '/auth/login';
  static const String authRegister = '/auth/register';
  static const String authMe = '/auth/me';
  static const String usersMe = '/users/me';
  static const String posts = '/posts';
  static const String users = '/users';
  static const String follows = '/follows';
  static const String messages = '/messages';
  static const String upload = '/upload';
  static const String usersMeFollowing = '/users/me/following';
  static const String usersMeFollowers = '/users/me/followers';
  static const String usersSearch = '/users/search';
  static const String friendRequests = '/friend-requests';
}
