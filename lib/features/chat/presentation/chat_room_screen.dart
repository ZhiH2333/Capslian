import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/layout_constants.dart';
import '../../auth/providers/auth_providers.dart';
import '../../direct/providers/chat_providers.dart' as ws_providers;
import '../data/models/sn_chat_message.dart';
import '../providers/chat_providers.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/im_message_list.dart';

/// 单聊/群聊房间页：双向消息列表 + 输入栏；支持发送文本/图片、加载更多、WebSocket 新消息。
class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.roomId,
    this.roomTitle,
  });

  final String roomId;
  final String? roomTitle;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  bool _loadMoreTriggered = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(roomMessagesProvider(widget.roomId).notifier).loadInitial(widget.roomId);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent - pos.pixels < 120 && !_loadMoreTriggered) {
      _loadMoreTriggered = true;
      ref.read(roomMessagesProvider(widget.roomId).notifier).loadMore(widget.roomId).then((_) {
        if (mounted) _loadMoreTriggered = false;
      });
    }
  }

  Future<void> _sendText() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    final repo = ref.read(chatRepositoryProvider);
    final nonce = const Uuid().v4();
    final me = ref.read(authStateProvider).valueOrNull?.id ?? '';
    final notifier = ref.read(roomMessagesProvider(widget.roomId).notifier);
    final optimistic = SnChatMessage(
      id: nonce,
      roomId: widget.roomId,
      senderId: me,
      content: text,
      createdAt: DateTime.now().toIso8601String(),
      nonce: nonce,
    );
    notifier.appendMessage(widget.roomId, optimistic);
    try {
      final msg = await repo.sendText(widget.roomId, content: text, nonce: nonce);
      if (msg != null && mounted) {
        notifier.replaceOrAppendMessage(widget.roomId, msg);
      }
    } catch (_) {}
  }

  Future<void> _sendImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 85);
    if (images.isEmpty || !mounted) return;
    final repo = ref.read(chatRepositoryProvider);
    final notifier = ref.read(roomMessagesProvider(widget.roomId).notifier);
    final me = ref.read(authStateProvider).valueOrNull?.id ?? '';
    for (final img in images) {
      final path = img.path;
      final nonce = const Uuid().v4();
      final optimistic = SnChatMessage(
        id: nonce,
        roomId: widget.roomId,
        senderId: me,
        content: '',
        createdAt: DateTime.now().toIso8601String(),
        nonce: nonce,
        attachments: [],
      );
      notifier.appendMessage(widget.roomId, optimistic);
      try {
        final msg = await repo.sendImage(widget.roomId, imagePath: path, nonce: nonce);
        if (msg != null && mounted) {
          notifier.replaceOrAppendMessage(widget.roomId, msg);
        }
      } catch (_) {}
    }
  }

  Future<void> _onLongPressMessage(SnChatMessage message) async {
    final meId = ref.read(authStateProvider).valueOrNull?.id ?? '';
    if (message.senderId != meId || message.isDeleted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('撤回消息'),
        content: const Text('确定要撤回这条消息吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('撤回'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(chatRepositoryProvider).deleteMessage(widget.roomId, message.id);
      if (mounted) {
        ref.read(roomMessagesProvider(widget.roomId).notifier).markDeleted(message.id);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Map<String, dynamic>>>(
      ws_providers.wsRawMessagesProvider,
      (Object? prev, AsyncValue<Map<String, dynamic>> next) {
        next.whenData((Map<String, dynamic> payload) {
          final roomId = (payload['room_id'] as Object?)?.toString() ??
              (payload['chat_room_id'] as Object?)?.toString() ?? '';
          if (roomId != widget.roomId) return;
          final type = payload['type'] as String?;
          if (type == 'messages.new' || type == 'messages.update' || type == 'messages.update.links') {
            final msgJson = payload['message'] as Map<String, dynamic>? ?? payload;
            try {
              final msg = SnChatMessage.fromJson(msgJson);
              ref.read(roomMessagesProvider(widget.roomId).notifier).replaceOrAppendMessage(widget.roomId, msg);
            } catch (_) {}
          } else if (type == 'messages.delete') {
            final id = (payload['message_id'] as Object?)?.toString() ??
                (payload['id'] as Object?)?.toString() ?? '';
            if (id.isNotEmpty) {
              ref.read(roomMessagesProvider(widget.roomId).notifier).markDeleted(id);
            }
          }
        });
      },
    );

    final messagesState = ref.watch(roomMessagesProvider(widget.roomId));
    final me = ref.watch(authStateProvider).valueOrNull?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomTitle ?? '聊天'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: messagesState.loading
                ? const Center(child: CircularProgressIndicator())
                : messagesState.error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(messagesState.error!),
                            const SizedBox(height: LayoutConstants.kSpacingLarge),
                            FilledButton(
                              onPressed: () => ref
                                  .read(roomMessagesProvider(widget.roomId).notifier)
                                  .loadInitial(widget.roomId),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : (messagesState.aboveCenter.isEmpty && messagesState.belowCenter.isEmpty)
                        ? const Center(child: Text('暂无消息'))
                        : ImMessageList(
                            scrollController: _scrollController,
                            aboveCenter: messagesState.aboveCenter,
                            belowCenter: messagesState.belowCenter,
                            currentUserId: me,
                            loadingMore: messagesState.loadingMore,
                            itemBuilder: (BuildContext context, SnChatMessage message) {
                              return ChatBubble(
                                message: message,
                                isMe: message.senderId == me,
                                onLongPress: _onLongPressMessage,
                              );
                            },
                          ),
          ),
          ChatInputBar(
            controller: _inputController,
            onSendText: _sendText,
            onSendImages: _sendImages,
          ),
        ],
      ),
    );
  }
}
