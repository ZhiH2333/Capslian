import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../auth/providers/auth_providers.dart';
import '../../social/providers/social_providers.dart';

/// 好友申请列表：查看收到的申请，接受或拒绝。
class FriendRequestsScreen extends ConsumerStatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  ConsumerState<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends ConsumerState<FriendRequestsScreen> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  String? _error;
  final Set<String> _processingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(socialRepositoryProvider);
      final list = await repo.getFriendRequestsReceived();
      if (mounted) {
        setState(() {
          _list = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        String message = e.toString().replaceFirst('Exception: ', '');
        if (e is DioException && e.response?.statusCode == 404) {
          message = '接口未找到(404)。请确认已部署最新版 Worker：在 cloudflare 目录执行 wrangler deploy';
        }
        setState(() {
          _error = message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _accept(String requestId) async {
    setState(() => _processingIds.add(requestId));
    try {
      final repo = ref.read(socialRepositoryProvider);
      await repo.acceptFriendRequest(requestId);
      if (mounted) {
        setState(() {
          _processingIds.remove(requestId);
          _list.removeWhere((Map<String, dynamic> r) => r['id'] == requestId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: ValueKey('accept_${DateTime.now().millisecondsSinceEpoch}'),
            content: const Text('已接受好友申请'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processingIds.remove(requestId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: ValueKey('accept_err_${DateTime.now().millisecondsSinceEpoch}'),
            content: Text('操作失败：${e.toString().replaceFirst('Exception: ', '')}'),
          ),
        );
      }
    }
  }

  Future<void> _reject(String requestId) async {
    setState(() => _processingIds.add(requestId));
    try {
      final repo = ref.read(socialRepositoryProvider);
      await repo.rejectFriendRequest(requestId);
      if (mounted) {
        setState(() {
          _processingIds.remove(requestId);
          _list.removeWhere((Map<String, dynamic> r) => r['id'] == requestId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: ValueKey('reject_${DateTime.now().millisecondsSinceEpoch}'),
            content: const Text('已拒绝'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processingIds.remove(requestId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: ValueKey('reject_err_${DateTime.now().millisecondsSinceEpoch}'),
            content: Text('操作失败：${e.toString().replaceFirst('Exception: ', '')}'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('好友申请')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('请先登录'),
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
        title: const Text('好友申请'),
        actions: <Widget>[
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
              tooltip: '刷新',
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : _list.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(Icons.mail_outline, size: 64, color: theme.colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(
                            '暂无好友申请',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '当有人向你发送好友申请时会显示在这里',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _list.length,
                        itemBuilder: (_, int i) {
                          final r = _list[i];
                          final id = r['id']?.toString() ?? '';
                          final username = r['username']?.toString() ?? '';
                          final displayName = r['display_name']?.toString() ?? '';
                          final avatarUrl = r['avatar_url']?.toString();
                          final name = displayName.isNotEmpty ? displayName : username;
                          final createdAt = r['created_at']?.toString() ?? '';
                          final isProcessing = _processingIds.contains(id);
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.primaryContainer,
                              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: avatarUrl == null || avatarUrl.isEmpty
                                  ? Text(
                                      name.isNotEmpty ? name[0] : '?',
                                      style: TextStyle(
                                        color: theme.colorScheme.onPrimaryContainer,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(name),
                            subtitle: username.isNotEmpty
                                ? Text(
                                    '@$username${createdAt.isNotEmpty ? ' · $createdAt' : ''}',
                                    style: theme.textTheme.bodySmall,
                                  )
                                : (createdAt.isNotEmpty ? Text(createdAt, style: theme.textTheme.bodySmall) : null),
                            trailing: isProcessing
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      TextButton(
                                        onPressed: () => _reject(id),
                                        child: const Text('拒绝'),
                                      ),
                                      const SizedBox(width: 4),
                                      FilledButton(
                                        onPressed: () => _accept(id),
                                        child: const Text('接受'),
                                      ),
                                    ],
                                  ),
                            onTap: null,
                          );
                        },
                      ),
                    ),
    );
  }
}
