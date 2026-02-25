import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_providers.dart';
import '../data/models/chat_room_model.dart';
import '../data/models/local_chat_message.dart';
import '../pods/chat_subscribe.dart';
import '../pods/messages_notifier.dart';
import 'widgets/chat_input.dart';
import 'widgets/message_item.dart';
import 'widgets/room_app_bar.dart';
import 'widgets/room_message_list.dart';

/// 聊天房间页面，集成消息列表、实时订阅、发送与操作。
class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({super.key, required this.room});

  final ChatRoom room;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  LocalChatMessage? _replyingTo;
  LocalChatMessage? _editingTo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatSubscribeProvider(widget.room.id));
    });
  }

  void _handleAction(MessageAction action, LocalChatMessage message) {
    switch (action) {
      case MessageAction.reply:
        setState(() {
          _replyingTo = message;
          _editingTo = null;
        });
      case MessageAction.edit:
        setState(() {
          _editingTo = message;
          _replyingTo = null;
        });
      case MessageAction.delete:
        _confirmDelete(message);
      case MessageAction.resend:
        _resendMessage(message);
      case MessageAction.forward:
        _showForwardDialog(message);
    }
  }

  Future<void> _confirmDelete(LocalChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('撤回消息'),
        content: const Text('确定撤回该消息吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '撤回',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await ref
        .read(messagesProvider(widget.room.id).notifier)
        .deleteMessage(message.id);
  }

  Future<void> _resendMessage(LocalChatMessage message) async {
    await ref
        .read(messagesProvider(widget.room.id).notifier)
        .sendMessage(message.content, message.attachments);
  }

  void _showForwardDialog(LocalChatMessage message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: ValueKey('forward_${DateTime.now().millisecondsSinceEpoch}'),
        content: const Text('转发功能即将开放'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(chatSubscribeProvider(widget.room.id));
    final me = ref.watch(authStateProvider).valueOrNull;
    final messagesAsync = ref.watch(messagesProvider(widget.room.id));
    return Scaffold(
      appBar: RoomAppBar(
        room: widget.room,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (_) {},
            itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'members',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.people_outline, size: 20),
                    SizedBox(width: 12),
                    Text('成员列表'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              data: (List<LocalChatMessage> messages) {
                if (messages.isEmpty) {
                  return const Center(child: Text('暂无消息，发一条开始聊天吧'));
                }
                return RoomMessageList(
                  roomId: widget.room.id,
                  currentUserId: me?.id ?? '',
                  messages: messages,
                  onAction: _handleAction,
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object err, _) =>
                  Center(child: Text('加载失败：$err')),
            ),
          ),
          ChatInput(
            roomId: widget.room.id,
            replyingTo: _replyingTo,
            editingTo: _editingTo,
            onClearReply: () => setState(() => _replyingTo = null),
            onClearEdit: () => setState(() => _editingTo = null),
          ),
        ],
      ),
    );
  }
}
