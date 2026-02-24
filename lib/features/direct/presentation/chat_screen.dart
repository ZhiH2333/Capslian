import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../auth/providers/auth_providers.dart';
import '../../social/providers/social_providers.dart';
import '../data/models/message_model.dart';
import '../providers/chat_providers.dart';

/// 与指定用户的私信聊天页（REST 初载 + WebSocket 实时接收 + 发送走 REST）。
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.peerUserId});
  final String peerUserId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _subscribeWs(WidgetRef ref, String peerUserId, String myId) {
    ref.listen(wsRawMessagesProvider, (Object? prev, AsyncValue<Map<String, dynamic>> next) {
      next.whenData((Map<String, dynamic> payload) {
        final type = payload['type'] as String?;
        if (type != 'message') return;
        final msg = payload['message'] as Map<String, dynamic>?;
        if (msg == null) return;
        final senderId = msg['sender_id']?.toString() ?? '';
        final receiverId = msg['receiver_id']?.toString() ?? '';
        final isForThisChat = (senderId == myId && receiverId == peerUserId) ||
            (receiverId == myId && senderId == peerUserId);
        if (!isForThisChat) return;
        ref.read(chatMessagesNotifierProvider(peerUserId).notifier).appendFromWs(MessageModel.fromJson(msg));
      });
    });
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    final me = ref.read(authStateProvider).valueOrNull;
    if (me == null) return;
    _controller.clear();
    final tempId = const Uuid().v4();
    final optimistic = MessageModel(
      id: tempId,
      senderId: me.id,
      receiverId: widget.peerUserId,
      content: content,
      createdAt: null,
      status: MessageStatus.sending,
    );
    final notifier = ref.read(chatMessagesNotifierProvider(widget.peerUserId).notifier);
    notifier.appendOptimistic(optimistic);
    try {
      final repo = ref.read(socialRepositoryProvider);
      final raw = await repo.sendMessage(widget.peerUserId, content);
      final serverMessage = MessageModel.fromJson(raw);
      if (mounted) notifier.replaceOrAppend(serverMessage);
    } catch (_) {
      if (mounted) notifier.markFailed(tempId);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
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
    _subscribeWs(ref, widget.peerUserId, me.id);
    final messagesAsync = ref.watch(chatMessagesNotifierProvider(widget.peerUserId));
    return Scaffold(
      appBar: AppBar(title: Text('与 ${widget.peerUserId} 聊天')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: messagesAsync.when(
              data: (List<MessageModel> list) {
                if (list.isEmpty) {
                  return const Center(child: Text('暂无消息，发一条开始聊天吧'));
                }
                return ListView.builder(
                  controller: _scrollController,
                  itemCount: list.length,
                  itemBuilder: (_, int i) {
                    final m = list[i];
                    final isMe = m.senderId == me.id;
                    return _MessageBubble(
                      message: m,
                      isMe: isMe,
                      showStatus: isMe,
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object err, StackTrace? _) => Center(child: Text('加载失败: $err')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: '输入消息...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showStatus,
  });

  final MessageModel message;
  final bool isMe;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    IconData? statusIcon;
    if (showStatus) {
      switch (message.status) {
        case MessageStatus.sending:
          statusIcon = Icons.schedule;
          break;
        case MessageStatus.sent:
          statusIcon = Icons.done;
          break;
        case MessageStatus.read:
          statusIcon = Icons.done_all;
          break;
        case MessageStatus.failed:
          statusIcon = Icons.error_outline;
          break;
      }
    }
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMe
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(message.content),
            ),
            if (statusIcon != null) ...<Widget>[
              const SizedBox(width: 4),
              Icon(statusIcon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
  }
}
