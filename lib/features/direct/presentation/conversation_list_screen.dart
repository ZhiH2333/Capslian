import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
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
      return Scaffold(
        appBar: AppBar(title: const Text('私信')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('请先登录'),
              TextButton(onPressed: () => context.go(AppRoutes.login), child: const Text('去登录')),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('私信')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _conversations.isEmpty
                  ? const Center(child: Text('暂无会话'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _conversations.length,
                        itemBuilder: (_, int i) {
                          final c = _conversations[i];
                          final peerId = c['peer_id']?.toString() ?? '';
                          final last = c['last_content']?.toString() ?? '';
                          final lastAt = c['last_at']?.toString() ?? '';
                          return ListTile(
                            title: Text(peerId),
                            subtitle: Text('$last $lastAt'),
                            onTap: () => context.push('${AppRoutes.direct}/$peerId'),
                          );
                        },
                      ),
                    ),
    );
  }
}
