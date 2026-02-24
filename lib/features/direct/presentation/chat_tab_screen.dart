import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/chat_providers.dart';
import '../../social/providers/social_providers.dart';

/// 聊天 Tab：会话列表 + 好友列表，可与好友发起或继续聊天。
class ChatTabScreen extends ConsumerStatefulWidget {
  const ChatTabScreen({super.key, required this.onOpenChat});

  final void Function(String peerId, [String? peerDisplayName]) onOpenChat;

  @override
  ConsumerState<ChatTabScreen> createState() => _ChatTabScreenState();
}

class _ChatTabScreenState extends ConsumerState<ChatTabScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _friends = [];
  bool _loading = true;
  String? _error;
  bool _didTriggerWsConnect = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(socialRepositoryProvider);
      final results = await Future.wait(<Future<dynamic>>[
        repo.getConversations(),
        repo.getFriends(),
      ]);
      if (mounted) {
        setState(() {
          _conversations = results[0] as List<Map<String, dynamic>>;
          _friends = results[1] as List<Map<String, dynamic>>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _openSearch() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      if (mounted) context.go(AppRoutes.login);
      return;
    }
    await context.push<void>(AppRoutes.userSearch);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user != null && !_didTriggerWsConnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _didTriggerWsConnect) return;
        ref.read(webSocketServiceProvider).connect();
        if (mounted) setState(() => _didTriggerWsConnect = true);
      });
    }
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('聊天')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('请先登录后查看聊天'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(AppRoutes.login),
                child: const Text('去登录'),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Tab>[Tab(text: '会话'), Tab(text: '好友')],
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.mail_outline),
            tooltip: '好友申请',
            onPressed: () => context.push(AppRoutes.friendRequests),
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: '新增好友',
            onPressed: _openSearch,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _load,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: <Widget>[
                    _buildConversationsList(),
                    _buildFriendsList(),
                  ],
                ),
    );
  }

  Widget _buildConversationsList() {
    if (_conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.chat_bubble_outline, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('暂无会话'),
            const SizedBox(height: 8),
            Text(
              '在「好友」中选择好友开始聊天，或点击右上角添加好友',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openSearch,
              icon: const Icon(Icons.person_add),
              label: const Text('搜索用户添加好友'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _conversations.length,
        itemBuilder: (_, int i) {
          final c = _conversations[i];
          final peerId = c['peer_id']?.toString() ?? '';
          final peerDisplayName = (c['peer_display_name']?.toString() ?? '').trim();
          final peerUsername = c['peer_username']?.toString() ?? '';
          final displayTitle = peerDisplayName.isNotEmpty
              ? peerDisplayName
              : (peerUsername.isNotEmpty ? peerUsername : peerId);
          final last = c['last_content']?.toString() ?? '';
          final lastAt = c['last_at']?.toString() ?? '';
          final unreadCount = c['unread_count'] is num ? (c['unread_count'] as num).toInt() : 0;
          return ListTile(
            title: Text(displayTitle),
            subtitle: Text('$last $lastAt'),
            trailing: unreadCount > 0
                ? CircleAvatar(
                    radius: 12,
                    backgroundColor: Theme.of(context).colorScheme.error,
                    child: Text(
                      unreadCount > 99 ? '99+' : unreadCount.toString(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onError,
                        fontSize: 12,
                      ),
                    ),
                  )
                : null,
            onTap: () => widget.onOpenChat(peerId, displayTitle),
          );
        },
      ),
    );
  }

  Widget _buildFriendsList() {
    if (_friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.people_outline, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('暂无好友'),
            const SizedBox(height: 8),
            Text(
              '点击右上角搜索并添加好友',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openSearch,
              icon: const Icon(Icons.person_add),
              label: const Text('搜索用户添加好友'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _friends.length,
        itemBuilder: (_, int i) {
          final f = _friends[i];
          final id = f['id']?.toString() ?? '';
          final displayName = (f['display_name']?.toString() ?? '').trim();
          final username = f['username']?.toString() ?? '';
          final title = displayName.isNotEmpty ? displayName : username;
          return ListTile(
            title: Text(title),
            subtitle: username != title ? Text(username) : null,
            leading: CircleAvatar(
              backgroundImage: f['avatar_url'] != null && f['avatar_url'].toString().isNotEmpty
                  ? NetworkImage(f['avatar_url'].toString())
                  : null,
              child: f['avatar_url'] == null || f['avatar_url'].toString().isEmpty
                  ? Text(title.isNotEmpty ? title[0].toUpperCase() : '?')
                  : null,
            ),
            onTap: () => widget.onOpenChat(id, title),
          );
        },
      ),
    );
  }
}
