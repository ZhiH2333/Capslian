import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';

import '../../../core/constants/layout_constants.dart';
import '../../auth/providers/auth_providers.dart';
import '../../direct/providers/chat_providers.dart' as ws_providers;
import '../data/chat_repository.dart';
import '../data/models/chat_message_dto.dart';
import '../providers/chat_providers.dart';

/// 将 [ChatMessageDto] 转为 flutter_chat_core v2 的 [Message]。
Message dtoToMessage(ChatMessageDto dto, String roomId) {
  final createdAt = _parseDateTime(dto.createdAt);
  final metadata = <String, dynamic>{
    if (dto.localId != null && dto.localId!.isNotEmpty)
      'local_id': dto.localId!,
  };
  if (dto.attachments.isNotEmpty && dto.attachments.first.isImage) {
    final att = dto.attachments.first;
    final source = ChatRepository.imageUrl(att.url);
    return Message.image(
      id: dto.id,
      authorId: dto.senderId,
      source: source,
      text: dto.content.isNotEmpty ? dto.content : null,
      createdAt: createdAt,
      metadata: metadata.isEmpty ? null : metadata,
    );
  }
  return Message.text(
    id: dto.id,
    authorId: dto.senderId,
    text: dto.content,
    createdAt: createdAt,
    metadata: metadata.isEmpty ? null : metadata,
  );
}

DateTime? _parseDateTime(String? s) {
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s.trim());
}

/// 单聊/群聊房间页：flutter_chat_ui v2 Chat + 历史升序、乐观更新（localId）、WebSocket 替换/追加。
class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({super.key, required this.roomId, this.roomTitle});

  final String roomId;
  final String? roomTitle;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  late final ChatController _chatController;
  bool _initialLoadDone = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _chatController = InMemoryChatController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialMessages());
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialMessages() async {
    if (!mounted) return;
    final repo = ref.read(chatRepositoryProvider);
    try {
      final list = await repo.fetchMessages(widget.roomId, offset: 0, take: 50);
      if (!mounted) return;
      final messages = list
          .map((ChatMessageDto dto) => dtoToMessage(dto, widget.roomId))
          .toList();
      await _chatController.setMessages(messages);
      if (mounted) {
        setState(() {
          _initialLoadDone = true;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initialLoadDone = true;
          _loadError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _onMessageSend(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final currentUserId = ref.read(authStateProvider).valueOrNull?.id ?? '';
    if (currentUserId.isEmpty) return;
    final localId = const Uuid().v4();
    final optimistic = Message.text(
      id: localId,
      authorId: currentUserId,
      text: trimmed,
      createdAt: DateTime.now(),
      metadata: <String, dynamic>{'local_id': localId, 'pending': true},
    );
    _chatController.insertMessage(optimistic);
    ref
        .read(chatRepositoryProvider)
        .sendText(widget.roomId, content: trimmed, localId: localId)
        .then((ChatMessageDto? msg) {
          if (msg != null && mounted) {
            _applyWebSocketMessage(msg);
          }
        })
        .catchError((Object _) {});
  }

  /// 应用 WebSocket 或 API 返回的消息：先按 local_id/nonce 匹配乐观消息，否则按 sender_id + pending 兜底，再否则 insert。
  void _applyWebSocketMessage(ChatMessageDto dto) {
    final incomingLocalId = dto.localId;
    final incomingSenderId = dto.senderId;
    final newMsg = dtoToMessage(dto, widget.roomId);
    final list = _chatController.messages;
    Message? matchedOptimistic;
    if (incomingLocalId != null && incomingLocalId.isNotEmpty) {
      for (final msg in list) {
        final meta = msg.metadata;
        if (meta != null && meta['local_id'] == incomingLocalId) {
          matchedOptimistic = msg;
          break;
        }
      }
    }
    if (matchedOptimistic == null) {
      for (final msg in list) {
        final meta = msg.metadata;
        if (msg.authorId == incomingSenderId &&
            meta != null &&
            meta['pending'] == true) {
          matchedOptimistic = msg;
          break;
        }
      }
    }
    if (matchedOptimistic != null) {
      _chatController.updateMessage(matchedOptimistic, newMsg);
      return;
    }
    if (list.any((Message m) => m.id == dto.id)) return;
    _chatController.insertMessage(newMsg);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Map<String, dynamic>>>(
      ws_providers.wsRawMessagesProvider,
      (Object? prev, AsyncValue<Map<String, dynamic>> next) {
        next.whenData((Map<String, dynamic> payload) {
          final roomId =
              (payload['room_id'] as Object?)?.toString() ??
              (payload['chat_room_id'] as Object?)?.toString() ??
              '';
          if (roomId != widget.roomId) return;
          final type = payload['type'] as String?;
          if (type == 'messages.new' ||
              type == 'messages.update' ||
              type == 'messages.update.links') {
            final msgJson =
                payload['message'] as Map<String, dynamic>? ?? payload;
            try {
              final dto = ChatMessageDto.fromJson(msgJson);
              _applyWebSocketMessage(dto);
            } catch (_) {}
          } else if (type == 'messages.delete') {
            final id =
                (payload['message_id'] as Object?)?.toString() ??
                (payload['id'] as Object?)?.toString() ??
                '';
            if (id.isNotEmpty) {
              final list = _chatController.messages;
              for (final msg in list) {
                if (msg.id == id) {
                  _chatController.removeMessage(msg);
                  break;
                }
              }
            }
          }
        });
      },
    );

    final currentUserId = ref.watch(authStateProvider).valueOrNull?.id ?? '';
    if (currentUserId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.roomTitle ?? '聊天'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: Text('请先登录')),
      );
    }

    if (!_initialLoadDone && _loadError == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.roomTitle ?? '聊天'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.roomTitle ?? '聊天'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(_loadError!),
              const SizedBox(height: LayoutConstants.kSpacingLarge),
              FilledButton(
                onPressed: _loadInitialMessages,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final surfaceColor = theme.colorScheme.surface;
    final chatTheme = ChatTheme.fromThemeData(theme);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomTitle ?? '聊天'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: <Widget>[
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (String value) async {
              if (value == 'clear') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext ctx) => AlertDialog(
                    title: const Text('清除聊天记录'),
                    content: const Text(
                      '仅清除你本地的记录，对方不受影响。再次进入会话将重新加载历史。确定清除？',
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('清除'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && mounted) {
                  await _chatController.setMessages(<Message>[]);
                  if (mounted) {
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(
                        content: Text('已清除聊天记录（仅自己可见）'),
                      ),
                    );
                  }
                }
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'clear',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.delete_sweep_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('清除聊天记录（仅自己可见）'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Chat(
        currentUserId: currentUserId,
        resolveUser: (UserID id) async =>
            User(id: id, name: id, imageSource: null),
        chatController: _chatController,
        theme: chatTheme,
        backgroundColor: surfaceColor,
        onMessageSend: _onMessageSend,
        onMessageLongPress: _onMessageLongPress,
      ),
    );
  }

  void _onMessageLongPress(
    BuildContext context,
    Message message, {
    required int index,
    required LongPressStartDetails details,
  }) {
    final currentUserId = ref.read(authStateProvider).valueOrNull?.id ?? '';
    if (currentUserId.isEmpty) return;
    if (message.authorId != currentUserId) return;
    final created = message.createdAt ?? DateTime(0);
    final withinFiveMin = DateTime.now().difference(created).inMinutes < 5;
    if (!withinFiveMin) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('撤回'),
          onTap: () async {
            Navigator.pop(sheetContext);
            try {
              await ref.read(chatRepositoryProvider).deleteMessage(
                    widget.roomId,
                    message.id,
                  );
            } on DioException catch (e) {
              if (!mounted) return;
              final status = e.response?.statusCode;
              final msg = status == 403
                  ? (e.response?.data is Map &&
                          (e.response!.data as Map)['error'] is String
                      ? (e.response!.data as Map)['error'] as String
                      : '超过 5 分钟无法撤回')
                  : '撤回失败，请重试';
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(content: Text(msg)),
              );
            }
          },
        ),
      ),
    );
  }
}
