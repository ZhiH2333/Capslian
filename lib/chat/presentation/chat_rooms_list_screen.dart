import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_chat_kits/flutter_chat_kits.dart';

import '../../../core/router/app_router.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/direct/providers/chat_providers.dart';
import '../../features/social/providers/social_providers.dart';
import '../chat_kits_backend.dart';
import '../pods/chat_room.dart';

/// 聊天 Tab 页：会话列表（flutter_chat_kits）+ 好友列表，点击进入 ChatBody 房间页。
class ChatRoomsListScreen extends ConsumerStatefulWidget {
  const ChatRoomsListScreen({super.key});

  @override
  ConsumerState<ChatRoomsListScreen> createState() =>
      _ChatRoomsListScreenState();
}

class _ChatRoomsListScreenState extends ConsumerState<ChatRoomsListScreen>
    with SingleTickerProviderStateMixin {
  bool _didConnectWs = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authStateProvider).valueOrNull;
    if (me == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('聊天')),
        body: const Center(child: Text('请先登录')),
      );
    }
    if (!_didConnectWs) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _didConnectWs) return;
        ref.read(webSocketServiceProvider).connect();
        if (mounted) setState(() => _didConnectWs = true);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '会话'),
            Tab(text: '好友'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.mail_outline),
            tooltip: '好友申请',
            onPressed: () => context.push(AppRoutes.friendRequests),
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: '搜索添加好友',
            onPressed: () => context.push(AppRoutes.userSearch),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              RoomManager.i.run();
              setState(() {});
            },
            tooltip: '刷新',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ConversationsTab(),
          _FriendsTab(),
        ],
      ),
    );
  }
}

/// 会话 Tab：RoomManager.i.rooms + ChatInbox，点击用 connect 打开房间页。
class _ConversationsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RoomManager.i,
      builder: (BuildContext context, Widget? child) {
        final rooms = RoomManager.i.rooms;
        if (rooms.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('暂无会话'),
                SizedBox(height: 8),
                Text(
                  '在「好友」中选择好友发起私信',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          itemCount: rooms.length,
          itemBuilder: (BuildContext context, int index) {
            final room = rooms[index];
            return InkWell(
              onTap: () async {
                await RoomManager.i.connect<void>(
                  context,
                  room,
                  onError: (String err) {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.clearSnackBars();
                    messenger.showSnackBar(SnackBar(key: const ValueKey('chat_connect_err'), content: Text(err)));
                  },
                );
              },
              child: ChatInbox(room: room),
            );
          },
        );
      },
    );
  }
}

/// 好友 Tab：从 social 拉取好友，点击创建/进入私信房间后跳转聊天。
class _FriendsTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends ConsumerState<_FriendsTab> {
  List<Map<String, dynamic>> _friends = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(socialRepositoryProvider);
      final list = await repo.getFriends();
      if (mounted) {
        setState(() {
          _friends = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _confirmRemoveFriend(String friendId, String friendName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定删除好友「$friendName」吗？删除后需重新发送好友申请才能恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final repo = ref.read(socialRepositoryProvider);
      await repo.removeFriend(friendId);
      if (mounted) {
        final me = ref.read(authStateProvider).valueOrNull?.id ?? '';
        for (final room in RoomManager.i.rooms) {
          if (room.isGroup) continue;
          final participants = room.participants.toList();
          if (participants.length == 2 &&
              participants.contains(friendId) &&
              participants.contains(me)) {
            RoomManager.i.pop(room.id);
            break;
          }
        }
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(key: const ValueKey('chat_friend_removed'), content: Text('已删除好友（${friendName.trim().isNotEmpty ? friendName : friendId}）')),
        );
        _loadFriends();
      }
    } catch (e) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(key: const ValueKey('chat_friend_remove_fail'), content: Text('删除失败：${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }

  Future<void> _openChatWithFriend(String friendId, String friendName) async {
    if (friendId.isEmpty) return;
    try {
      final room = await ref.read(chatRoomListProvider.notifier).fetchOrCreateDirectRoom(friendId);
      if (!mounted) return;
      final kitsRoom = Room.parse(chatRoomToKitsMap(room, directPeerId: friendId));
      if (kitsRoom.isEmpty) {
        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          messenger.clearSnackBars();
          messenger.showSnackBar(SnackBar(key: const ValueKey('chat_open_room_fail'), content: const Text('无法打开会话，请稍后重试')));
        }
        return;
      }
      RoomManager.i.put(kitsRoom);
      await RoomManager.i.connect<void>(
        context,
        kitsRoom,
        onError: (String err) {
          if (mounted) {
            final messenger = ScaffoldMessenger.of(context);
            messenger.clearSnackBars();
            messenger.showSnackBar(SnackBar(key: const ValueKey('chat_connect_err_2'), content: Text(err)));
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('无法发起会话'),
          content: Text(errorMessage),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('加载失败：$_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _loadFriends,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('暂无好友'),
            const SizedBox(height: 8),
            Text(
              '发送好友申请后，对方接受才会成为好友，才能发起私信',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push(AppRoutes.userSearch),
              icon: const Icon(Icons.person_search),
              label: const Text('搜索添加好友'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFriends,
      child: ListView.builder(
        itemCount: _friends.length,
        itemBuilder: (BuildContext context, int i) {
          final f = _friends[i];
          final id = f['id']?.toString() ?? '';
          final displayName = (f['display_name']?.toString() ?? '').trim();
          final username = f['username']?.toString() ?? '';
          final title = displayName.isNotEmpty ? displayName : username;
          final avatarUrl = f['avatar_url']?.toString();
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Text(
                      title.isNotEmpty ? title[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                    )
                  : null,
            ),
            title: Text(title),
            subtitle: username.isNotEmpty ? Text('@$username') : null,
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (String value) {
                if (value == 'delete') _confirmRemoveFriend(id, title);
              },
              itemBuilder: (BuildContext context) => [
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.person_remove, size: 20),
                      SizedBox(width: 12),
                      Text('删除好友'),
                    ],
                  ),
                ),
              ],
            ),
            onTap: () => _openChatWithFriend(id, title),
          );
        },
      ),
    );
  }
}
