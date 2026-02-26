import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_chat_kits/flutter_chat_kits.dart';
import 'package:go_router/go_router.dart';

import '../../../chat/chat_kits_backend.dart';
import '../../../chat/pods/chat_room.dart';
import '../../../core/router/app_router.dart';

/// /direct/:peerId 重定向：拉取或创建私信房间后，用 flutter_chat_kits 打开聊天页，关闭后返回会话列表。
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
      final kitsRoom = Room.parse(chatRoomToKitsMap(room));
      if (kitsRoom.isEmpty) {
        if (mounted) context.go(AppRoutes.chatRooms);
        return;
      }
      RoomManager.i.put(kitsRoom);
      await RoomManager.i.connect<void>(
        context,
        kitsRoom,
        onError: (String err) {
          if (mounted) setState(() => _error = err);
        },
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      return;
    }
    if (mounted) context.go(AppRoutes.chatRooms);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('发起会话')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
