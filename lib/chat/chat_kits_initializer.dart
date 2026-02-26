import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_chat_kits/flutter_chat_kits.dart';

import 'chat_kits_backend.dart';
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
              if (!msg.isEmpty) _messageDelegate?.appendOrUpdateMessage(roomId, msg);
            } catch (_) {}
          } else if (type == 'messages.update' || type == 'messages.update.links') {
            final msgJson = payload['message'] as Map<String, dynamic>? ?? payload;
            try {
              final sn = SnChatMessage.fromJson(msgJson);
              final msg = Message.parse(snMessageToKitsMap(sn));
              if (!msg.isEmpty) _messageDelegate?.appendOrUpdateMessage(roomId, msg);
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
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: profile.photo != null && profile.photo!.isNotEmpty
                    ? NetworkImage(profile.photo!)
                    : null,
                child: profile.photo == null || profile.photo!.isEmpty
                    ? Text(profile.nameSymbol)
                    : null,
              ),
              title: Text(profile.name.isEmpty ? room.id : profile.name),
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
            return AppBar(
              title: Text(configs.profile.name.isEmpty ? configs.manager.room.id : configs.profile.name),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            );
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
      RoomManager.i.deattach();
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
          RoomManager.i.deattach();
        }
      });
    });
    ref.listen(wsRawMessagesProvider, (Object? prev, AsyncValue<Map<String, dynamic>> next) {
      next.whenData((Map<String, dynamic> payload) {
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return widget.child;
  }
}

/// 单聊房间页：AppBar + ChatBody。
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
      body: ChatBody(manager: widget.manager),
    );
  }
}
