import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../chat/providers/chat_providers.dart';

/// /direct/:peerId 重定向：拉取或创建私信房间后跳转到 ChatRoomScreen。
class DirectToChatRedirectScreen extends ConsumerStatefulWidget {
  const DirectToChatRedirectScreen({
    super.key,
    required this.peerId,
    this.peerDisplayName,
  });

  final String peerId;
  final String? peerDisplayName;

  @override
  ConsumerState<DirectToChatRedirectScreen> createState() =>
      _DirectToChatRedirectScreenState();
}

class _DirectToChatRedirectScreenState
    extends ConsumerState<DirectToChatRedirectScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openChat());
  }

  Future<void> _openChat() async {
    if (widget.peerId.isEmpty) {
      if (mounted) context.go(AppRoutes.chatRooms);
      return;
    }
    try {
      final room = await ref.read(chatRoomListProvider.notifier).fetchOrCreateDirectRoom(widget.peerId);
      if (!mounted) return;
      final title = room.name.isNotEmpty ? room.name : (widget.peerDisplayName ?? widget.peerId);
      context.push(AppRoutes.chatRoom(room.id), extra: <String, String>{'title': title});
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('发起会话')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(AppRoutes.chatRooms),
                child: const Text('返回聊天'),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('发起会话')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
