import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/direct/providers/chat_providers.dart';
import '../../features/social/providers/social_providers.dart';
import '../data/models/chat_room_model.dart';
import '../data/models/local_chat_message.dart';
import '../pods/chat_room.dart';

/// 聊天 Tab 页：会话列表 + 好友列表。
/// 流程：发送好友申请（搜索用户）→ 对方在「好友申请」中接受/拒绝 → 接受后成为好友 → 在「好友」中可发起私信。
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
              ref.read(chatRoomListProvider.notifier).fetchRooms();
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

/// 会话 Tab：已有聊天房间列表。
class _ConversationsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(chatRoomListProvider);
    return roomsAsync.when(
      data: (List<ChatRoom> rooms) {
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
        return RefreshIndicator(
          onRefresh: () =>
              ref.read(chatRoomListProvider.notifier).fetchRooms(),
          child: ListView.builder(
            itemCount: rooms.length,
            itemBuilder: (_, int i) => _RoomTile(room: rooms[i]),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object err, _) => Center(child: Text('加载失败：$err')),
    );
  }
}

/// 好友 Tab：仅显示已成为好友的用户，点击发起私信（接受申请后才成为好友，才能聊天）。
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

  Future<void> _openChatWithFriend(String friendId, String friendName) async {
    if (friendId.isEmpty) return;
    final roomNotifier = ref.read(chatRoomListProvider.notifier);
    try {
      final room = await roomNotifier.fetchOrCreateDirectRoom(friendId);
      if (!mounted) return;
      context.push('/chat/${room.id}', extra: room);
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
        itemBuilder: (_, int i) {
          final f = _friends[i];
          final id = f['id']?.toString() ?? '';
          final displayName =
              (f['display_name']?.toString() ?? '').trim();
          final username = f['username']?.toString() ?? '';
          final title =
              displayName.isNotEmpty ? displayName : username;
          final avatarUrl = f['avatar_url']?.toString();
          return ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  Theme.of(context).colorScheme.secondaryContainer,
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Text(
                      title.isNotEmpty ? title[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer,
                      ),
                    )
                  : null,
            ),
            title: Text(title),
            subtitle:
                username.isNotEmpty ? Text('@$username') : null,
            trailing: const Icon(Icons.chat_bubble_outline),
            onTap: () => _openChatWithFriend(id, title),
          );
        },
      ),
    );
  }
}

/// 会话列表单项，DM 显示最新消息预览，群组显示成员数。
class _RoomTile extends ConsumerWidget {
  const _RoomTile({required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (room.isDirect) {
      return _DirectRoomTile(room: room);
    }
    return _GroupRoomTile(room: room);
  }
}

/// DM 会话行：头像 + 对方名称（右上角时间）+ 最新消息预览。
class _DirectRoomTile extends ConsumerWidget {
  const _DirectRoomTile({required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastMsgAsync = ref.watch(roomLastMessageProvider(room.id));
    final lastMsg = lastMsgAsync.valueOrNull;
    final preview = _buildPreview(lastMsg);
    final timeStr = lastMsg?.createdAt != null
        ? _formatConvTime(lastMsg!.createdAt!)
        : '';
    return InkWell(
      onTap: () => context.push('/chat/${room.id}', extra: room),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _RoomAvatar(room: room),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (timeStr.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildPreview(LocalChatMessage? msg) {
    if (msg == null) return '';
    if (msg.isDeleted) return '[消息已撤回]';
    if (msg.content.isNotEmpty) return msg.content;
    if (msg.attachments.isNotEmpty) return '[图片]';
    return '';
  }

  /// 格式化会话列表时间：今天显示 HH:mm，昨天显示「昨天」，更早显示 MM/dd。
  String _formatConvTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(local.year, local.month, local.day);
    if (msgDay == today) {
      return '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';
    }
    if (today.difference(msgDay).inDays == 1) return '昨天';
    return '${local.month.toString().padLeft(2, '0')}/'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

/// 群组会话行：头像 + 名称 + 成员数。
class _GroupRoomTile extends StatelessWidget {
  const _GroupRoomTile({required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _RoomAvatar(room: room),
      title: Text(
        room.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: room.memberCount > 0
          ? Text(
              '${room.memberCount} 位成员',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/chat/${room.id}', extra: room),
    );
  }
}

/// 房间头像：优先显示 avatarUrl，否则显示名称首字母。
class _RoomAvatar extends StatelessWidget {
  const _RoomAvatar({required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    final initial =
        room.name.isNotEmpty ? room.name[0].toUpperCase() : '?';
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      child: room.avatarUrl != null
          ? ClipOval(
              child: Image.network(
                room.avatarUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Text(
                  initial,
                  style: TextStyle(
                    color:
                        Theme.of(context).colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          : Text(
              initial,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }
}
