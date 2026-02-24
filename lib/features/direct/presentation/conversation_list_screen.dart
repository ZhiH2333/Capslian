import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_background.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../auth/providers/auth_providers.dart';
import '../../social/providers/social_providers.dart';

/// 私信会话列表；点击进入与对应用户的聊天页。
class ConversationListScreen extends ConsumerStatefulWidget {
  const ConversationListScreen({super.key});

  @override
  ConsumerState<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends ConsumerState<ConversationListScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;
  String? _error;

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
      final list = await repo.getConversations();
      if (mounted) {
        setState(() {
          _conversations = list;
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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) {
      return AppBackground(
        isRoot: true,
        child: Scaffold(
          appBar: AppBar(title: const Text('私信')),
          body: EmptyState(
            title: '请先登录',
            description: '登录后查看私信会话',
            action: FilledButton(
              onPressed: () => context.go(AppRoutes.login),
              child: const Text('去登录'),
            ),
          ),
        ),
      );
    }
    return AppBackground(
      isRoot: true,
      child: Scaffold(
        appBar: AppBar(title: const Text('私信')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? EmptyState(title: '加载失败', description: _error!)
                : _conversations.isEmpty
                    ? const EmptyState(
                        title: '暂无会话',
                        description: '和好友聊天会显示在这里',
                        icon: Icons.chat_bubble_outline,
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.paddingOf(context).bottom + LayoutConstants.kSpacingXLarge,
                          ),
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
                            final path = '${AppRoutes.direct}/$peerId';
                            final pushPath = displayTitle != peerId
                                ? '$path?peerName=${Uri.encodeComponent(displayTitle)}'
                                : path;
                            return ListTile(
                              contentPadding: LayoutConstants.kListTileContentPadding,
                              minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
                              title: Text(displayTitle),
                              subtitle: Text('$last $lastAt'),
                              onTap: () => context.push(pushPath),
                            );
                          },
                        ),
                      ),
      ),
    );
  }
}
