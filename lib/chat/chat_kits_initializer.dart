import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/platform_utils_stub.dart'
    if (dart.library.io) '../core/platform_utils_io.dart' as platform_utils;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_chat_kits/flutter_chat_kits.dart';
import 'package:image_picker/image_picker.dart';

import 'chat_kits_backend.dart' show MolianChatBackend, snMessageToKitsMap, toAbsoluteImageUrl;
import 'chat_kits_delegates.dart';
import '../core/network/dio_provider.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/direct/providers/chat_providers.dart';
import 'data/models/sn_chat_message.dart';

/// 全局只初始化一次 RoomManager 的标记。
bool _roomManagerInitialized = false;

/// 在已登录且 Dio 可用时初始化 RoomManager，并监听 WebSocket 将新消息推送给 delegate。
class ChatKitsInitializer extends ConsumerStatefulWidget {
  const ChatKitsInitializer({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ChatKitsInitializer> createState() =>
      _ChatKitsInitializerState();
}

class _ChatKitsInitializerState extends ConsumerState<ChatKitsInitializer> {
  bool _initDone = false;
  MolianChatMessageDelegate? _messageDelegate;
  MolianChatRoomDelegate? _roomDelegate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAsync());
  }

  Future<void> _initAsync() async {
    if (!mounted) return;
    final dio = ref.read(dioProvider);
    final uid = ref.read(authStateProvider).valueOrNull?.id ?? '';
    MolianChatBackend.set(dio, uid);
    if (!_roomManagerInitialized) {
      _roomManagerInitialized = true;
      final messageStreams = <String, StreamController<List<Message>>>{};
      final roomController = StreamController<bool>.broadcast();
      _messageDelegate = MolianChatMessageDelegate(messageStreams);
      _roomDelegate = MolianChatRoomDelegate(roomController);
      MolianChatBackend.setWsHandler(
        (String roomId, Map<String, dynamic> payload) {
          final type = payload['type'] as String?;
          if (type == 'messages.new') {
            final msgJson = payload['message'] as Map<String, dynamic>? ?? payload;
            try {
              final sn = SnChatMessage.fromJson(msgJson);
              final msg = Message.parse(snMessageToKitsMap(sn));
              if (!msg.isEmpty) {
                _messageDelegate?.appendOrUpdateMessage(
                  roomId,
                  msg,
                  clientNonce: sn.nonce,
                  senderId: sn.senderId,
                );
              }
            } catch (_) {}
          } else if (type == 'messages.update' || type == 'messages.update.links') {
            final msgJson = payload['message'] as Map<String, dynamic>? ?? payload;
            try {
              final sn = SnChatMessage.fromJson(msgJson);
              final msg = Message.parse(snMessageToKitsMap(sn));
              if (!msg.isEmpty) {
                _messageDelegate?.appendOrUpdateMessage(
                  roomId,
                  msg,
                  clientNonce: sn.nonce,
                  senderId: sn.senderId,
                );
              }
            } catch (_) {}
          } else if (type == 'messages.delete') {
            final messageId = (payload['message_id'] as Object?)?.toString() ??
                (payload['id'] as Object?)?.toString() ??
                '';
            if (messageId.isNotEmpty) {
              _messageDelegate?.removeOrMarkDeleted(roomId, messageId);
            }
          }
        },
        (_) {
          _roomDelegate?.refreshRooms();
        },
      );
      RoomManager.init(
        connectivity: Stream<bool>.periodic(
          const Duration(seconds: 30),
          (_) => true,
        ).asBroadcastStream(),
        room: _roomDelegate!,
        message: _messageDelegate!,
        status: MolianChatStatusDelegate(),
        typing: MolianChatTypingDelegate(),
        profile: MolianChatProfileDelegate(),
        notification: MolianChatNotificationDelegate(),
        normalizer: MolianChatNormalizer(),
        uiConfigs: ChatUiConfigs(
          directInboxBuilder: (BuildContext context, DirectRoom room, profile, status, typing) {
            final String roomName = room.extra['roomName']?.toString().trim() ?? '';
            final String displayName = (profile.name ?? '').trim().isNotEmpty
                ? (profile.name ?? '').trim()
                : roomName.isNotEmpty
                    ? roomName
                    : room.id;
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: profile.photo != null && profile.photo!.isNotEmpty
                    ? NetworkImage(profile.photo!)
                    : null,
                child: profile.photo == null || profile.photo!.isEmpty
                    ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')
                    : null,
              ),
              title: Text(displayName),
              subtitle: Text(room.formattedLastMessage(isTyping: typing != null && !typing.isEmpty)),
            );
          },
          groupInboxBuilder: (BuildContext context, GroupRoom room, profile, status, typings) {
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: room.photo != null && room.photo!.isNotEmpty
                    ? NetworkImage(room.photo!)
                    : null,
                child: Text(
                  room.name != null && room.name!.isNotEmpty
                      ? room.name![0].toUpperCase()
                      : '?',
                ),
              ),
              title: Text(room.name ?? ''),
              subtitle: Text(room.formattedLastMessage()),
            );
          },
          chatAppbarBuilder: (BuildContext context, ChatAppbarConfigs configs) {
            final room = configs.manager.room;
            final String roomName = room.extra['roomName']?.toString().trim() ?? '';
            final String titleText = (configs.profile.name ?? '').isNotEmpty
                ? (configs.profile.name ?? '')
                : roomName.isNotEmpty
                    ? roomName
                    : room.id;
            return AppBar(
              title: Text(titleText),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            );
          },
          inputBuilder: (BuildContext context, ChatInputConfigs configs) {
            return _ChatInputBar(configs: configs);
          },
          textBuilder: (BuildContext context, ChatManager manager, TextMessage msg) {
            return _ChatTextBubble(manager: manager, message: msg);
          },
          imageBuilder: (BuildContext context, ChatManager manager, ImageMessage msg) {
            return _ChatImageBubble(manager: manager, message: msg);
          },
          deletedBuilder: (BuildContext context, ChatManager manager, Message msg) {
            return _ChatDeletedBubble(message: msg);
          },
          noMessagesBuilder: (BuildContext context) {
            return const _ChatSystemMessage(text: '暂无消息');
          },
          onMutiImagePicker: (BuildContext context) async {
            if (platform_utils.isDesktopMacOS || platform_utils.isDesktopWindows) {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.image,
                allowMultiple: true,
              );
              if (result == null || result.files.isEmpty) return <String>[];
              return result.files
                  .map((e) => e.path)
                  .whereType<String>()
                  .where((String p) => p.isNotEmpty)
                  .toList();
            }
            final picker = ImagePicker();
            final images = await picker.pickMultiImage(imageQuality: 85);
            return images.map((f) => f.path).toList();
          },
          onChatStart: (BuildContext context, ChatManager manager) async {
            return Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => _ChatRoomPage(manager: manager),
              ),
            );
          },
        ),
      );
    }
    if (uid.isNotEmpty) {
      RoomManager.i.attach(uid);
    } else {
      RoomManager.i.detach();
    }
    if (mounted) setState(() => _initDone = true);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (Object? prev, AsyncValue<dynamic> next) {
      next.whenData((dynamic user) {
        final uid = user?.id?.toString() ?? '';
        MolianChatBackend.set(ref.read(dioProvider), uid);
        if (uid.isNotEmpty) {
          RoomManager.i.attach(uid);
        } else {
          RoomManager.i.detach();
        }
      });
    });
    ref.listen(wsRawMessagesProvider, (Object? prev, AsyncValue<Map<String, dynamic>> next) {
      next.whenData((Map<String, dynamic> payload) {
        final uid = ref.read(authStateProvider).valueOrNull?.id ?? MolianChatBackend.uid;
        if (uid.isNotEmpty && RoomManager.i.me != uid) {
          RoomManager.i.attach(uid);
        }
        String roomId = (payload['room_id'] as Object?)?.toString() ??
            (payload['chat_room_id'] as Object?)?.toString() ?? '';
        if (roomId.isEmpty && payload['message'] is Map) {
          final msg = payload['message'] as Map;
          roomId = (msg['room_id'] ?? msg['chat_room_id'])?.toString() ?? '';
        }
        if (roomId.isNotEmpty) {
          MolianChatBackend.handleWsMessage(roomId, payload);
        }
      });
    });
    if (!_initDone) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Scaffold(
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return widget.child;
  }
}

class _ChatSystemMessage extends StatelessWidget {
  const _ChatSystemMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ),
    );
  }
}

String _formatMessageTime(ChatValueTimestamp ts) {
  if (ts.isEmpty) return '';
  final dt = ts.timestamp.toLocal();
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  final timeStr = '$hh:$mm';
  if (timeStr == '00:00') {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final diffMin = now.difference(dt).inMinutes;
    if (isToday && diffMin >= 0 && diffMin < 60) return '刚刚';
  }
  return timeStr;
}

Future<void> _showMessageActions(
  BuildContext context,
  ChatManager manager,
  Message message,
) async {
  if (!message.isSentByMe || message.isDeleted || message.isSending) return;
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('撤回消息'),
              onTap: () {
                Navigator.of(ctx).pop();
                manager.delete(message);
              },
            ),
          ],
        ),
      );
    },
  );
}

class _ChatTextBubble extends StatelessWidget {
  const _ChatTextBubble({required this.manager, required this.message});

  final ChatManager manager;
  final TextMessage message;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isSentByMe;
    final theme = Theme.of(context);
    final bg = isMe ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
    final fg = isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant;
    final time = _formatMessageTime(message.createdAt);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageActions(context, manager, message),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  message.text,
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                ),
              ),
              if (time.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  time,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatDeletedBubble extends StatelessWidget {
  const _ChatDeletedBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isSentByMe;
    final theme = Theme.of(context);
    final time = _formatMessageTime(message.createdAt);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              '消息已撤回',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (time.isNotEmpty)
              Text(
                time,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatImageBubble extends StatelessWidget {
  const _ChatImageBubble({required this.manager, required this.message});

  final ChatManager manager;
  final ImageMessage message;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isSentByMe;
    final theme = Theme.of(context);
    final time = _formatMessageTime(message.createdAt);
    final rawUrl = message.urls.isNotEmpty ? message.urls.first : '';
    final firstUrl = toAbsoluteImageUrl(rawUrl);
    final isNetwork = firstUrl.isNotEmpty;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageActions(context, manager, message),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: isNetwork
                    ? CachedNetworkImage(
                        imageUrl: firstUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const _ImagePlaceholder(text: '加载中...'),
                        errorWidget: (_, __, ___) =>
                            const _ImagePlaceholder(text: '图片加载失败'),
                      )
                    : const _ImagePlaceholder(text: '图片上传中...'),
              ),
              if (message.caption != null && message.caption!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  message.caption!,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (time.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  time,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 140,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  const _ChatInputBar({required this.configs});

  final ChatInputConfigs configs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Material(
          elevation: 2,
          shadowColor: theme.shadowColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(24),
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: configs.onSendImages,
                  icon: const Icon(Icons.image_outlined),
                ),
                Expanded(
                  child: TextField(
                    controller: configs.editor,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => configs.onSendText(),
                    decoration: InputDecoration(
                      hintText: '输入消息',
                      isDense: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: configs.editor,
                  builder: (context, child) {
                    final enabled = configs.editor.text.trim().isNotEmpty;
                    return IconButton(
                      onPressed: enabled ? configs.onSendText : null,
                      icon: const Icon(Icons.send),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 聊天内容区：消息列表带底部留白，最新消息在输入面板上方可见；回复预览 + 输入栏与 ChatBody 一致。
class _ChatBodyWithFloatingInput extends StatelessWidget {
  const _ChatBodyWithFloatingInput({required this.manager});

  final ChatManager manager;

  @override
  Widget build(BuildContext context) {
    final i = RoomManager.i.uiConfigs;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: ChatBoard(manager: manager),
          ),
        ),
        ListenableBuilder(
          listenable: manager,
          builder: (_, __) {
            final reply = manager.replyMsg;
            if (reply == null || i.replayMessageReplyBuilder == null) {
              return const SizedBox.shrink();
            }
            return i.replayMessageReplyBuilder!(
              context,
              reply,
              () => manager.reply(null),
            );
          },
        ),
        ListenableBuilder(
          listenable: manager,
          builder: (_, __) {
            if (manager.room.isLeaveByMe) {
              return i.leaveFromRoomBuilder != null
                  ? i.leaveFromRoomBuilder!(context)
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: Text("You're unable to send message", style: Theme.of(context).textTheme.bodyMedium),
                    );
            }
            if (manager.room.isBlockByMe) {
              return i.blockedInputBuilder != null
                  ? i.blockedInputBuilder!(context)
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: Text("You're unable to send message", style: Theme.of(context).textTheme.bodyMedium),
                    );
            }
            return ChatInput(manager: manager);
          },
        ),
      ],
    );
  }
}

/// 单聊房间页：AppBar + 带底部留白的 ChatBody + 浮动输入。
class _ChatRoomPage extends StatefulWidget {
  const _ChatRoomPage({required this.manager});

  final ChatManager manager;

  @override
  State<_ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<_ChatRoomPage> {
  @override
  void initState() {
    super.initState();
    widget.manager.connect();
  }

  @override
  void dispose() {
    widget.manager.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ChatAppbar(manager: widget.manager),
      body: _ChatBodyWithFloatingInput(manager: widget.manager),
    );
  }
}
