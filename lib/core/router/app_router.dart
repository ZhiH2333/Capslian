import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../chat/data/models/chat_room_model.dart';
import '../../chat/presentation/chat_room_screen.dart';
import '../../chat/presentation/chat_rooms_list_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/posts/data/models/post_model.dart';
import '../../features/posts/presentation/create_post_screen.dart';
import '../../features/posts/presentation/post_comments_screen.dart';
import '../../features/posts/presentation/post_detail_screen.dart';
import '../../features/direct/presentation/chat_screen.dart';
import '../../features/direct/presentation/friend_requests_screen.dart';
import '../../features/direct/presentation/user_search_screen.dart';
import '../../features/discovery/presentation/explore_screen.dart';
import '../../features/files/presentation/files_screen.dart';
import '../../features/main_shell/presentation/main_shell_screen.dart';
import '../../features/realms/presentation/realms_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

/// 路由路径常量。
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String profile = '/profile';
  static const String createPost = '/posts/create';
  static const String settings = '/settings';
  static const String userSearch = '/users/search';
  static const String friendRequests = '/friend-requests';
  static const String explore = '/explore';
  static const String realms = '/realms';
  static const String files = '/files';
  static const String direct = '/direct';
  static String directConversation(String peerId) => '/direct/$peerId';
  static const String chatRooms = '/chat';
  static String chatRoom(String roomId) => '/chat/$roomId';
}

/// 配置 go_router，含底部导航壳（浏览、聊天、个人）。
GoRouter createAppRouter() {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        builder: (BuildContext context, GoRouterState state) =>
            const MainShellScreen(),
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
        path: '/posts/:id',
        builder: (BuildContext context, GoRouterState state) {
          final String id = state.pathParameters['id'] ?? '';
          final PostModel? initialPost = state.extra as PostModel?;
          return PostDetailScreen(postId: id, initialPost: initialPost);
        },
      ),
      GoRoute(
        path: '/posts/:id/comments',
        builder: (BuildContext context, GoRouterState state) {
          final String id = state.pathParameters['id'] ?? '';
          return PostCommentsScreen(postId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.userSearch,
        builder: (BuildContext context, GoRouterState state) =>
            const UserSearchScreen(),
      ),
      GoRoute(
        path: AppRoutes.friendRequests,
        builder: (BuildContext context, GoRouterState state) =>
            const FriendRequestsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.explore,
        builder: (BuildContext context, GoRouterState state) =>
            const ExploreScreen(),
      ),
      GoRoute(
        path: AppRoutes.realms,
        builder: (BuildContext context, GoRouterState state) =>
            const RealmsScreen(),
      ),
      GoRoute(
        path: AppRoutes.files,
        builder: (BuildContext context, GoRouterState state) =>
            const FilesScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.direct}/:peerId',
        builder: (BuildContext context, GoRouterState state) {
          final peerId = state.pathParameters['peerId'] ?? '';
          final peerName = state.uri.queryParameters['peerName'];
          return ChatScreen(peerUserId: peerId, peerDisplayName: peerName);
        },
      ),
      GoRoute(
        path: AppRoutes.chatRooms,
        builder: (BuildContext context, GoRouterState state) =>
            const ChatRoomsListScreen(),
      ),
      GoRoute(
        path: '/chat/:roomId',
        builder: (BuildContext context, GoRouterState state) {
          final roomId = state.pathParameters['roomId'] ?? '';
          final room = state.extra as ChatRoom?;
          if (room != null) return ChatRoomScreen(room: room);
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('房间 $roomId 不存在')),
          );
        },
      ),
    ],
  );
}
