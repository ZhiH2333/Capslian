import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/posts/presentation/create_post_screen.dart';
import '../../features/posts/presentation/home_screen.dart';
import '../../features/posts/presentation/post_comments_screen.dart';
import '../../features/direct/presentation/chat_screen.dart';
import '../../features/direct/presentation/conversation_list_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

/// 路由路径常量。
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String profile = '/profile';
  static const String createPost = '/posts/create';
  static const String direct = '/direct';
  static const String settings = '/settings';
}

/// 配置 go_router，含占位首页、登录、注册。
GoRouter createAppRouter() {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        builder: (BuildContext context, GoRouterState state) =>
            const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (BuildContext context, GoRouterState state) =>
            const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (BuildContext context, GoRouterState state) =>
            const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (BuildContext context, GoRouterState state) =>
            const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.createPost,
        builder: (BuildContext context, GoRouterState state) =>
            const CreatePostScreen(),
      ),
      GoRoute(
        path: '/posts/:id/comments',
        builder: (BuildContext context, GoRouterState state) {
          final id = state.pathParameters['id'] ?? '';
          return PostCommentsScreen(postId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.direct,
        builder: (BuildContext context, GoRouterState state) =>
            const ConversationListScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.direct}/:userId',
        builder: (BuildContext context, GoRouterState state) {
          final userId = state.pathParameters['userId'] ?? '';
          return ChatScreen(peerUserId: userId);
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsScreen(),
      ),
    ],
  );
}
