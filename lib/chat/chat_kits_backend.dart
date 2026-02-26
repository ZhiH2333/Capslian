import 'package:dio/dio.dart';
import 'package:flutter_chat_kits/flutter_chat_kits.dart';

import 'data/models/chat_room_model.dart';
import 'data/models/sn_chat_message.dart';

/// 供 flutter_chat_kits 的 delegates 使用的后端桥接（Dio、当前用户、WebSocket 事件）。
/// 由应用在登录后设置，登出时清空。
class MolianChatBackend {
  MolianChatBackend._();

  static Dio? _dio;
  static String _uid = '';
  static void Function(String roomId, Map<String, dynamic> payload)?
      _onWsMessage;
  static void Function(String roomId)? _onRoomRefresh;

  static Dio? get dio => _dio;
  static String get uid => _uid;

  static void set(Dio? dio, String uid) {
    _dio = dio;
    _uid = uid;
  }

  static void setWsHandler(
    void Function(String roomId, Map<String, dynamic> payload)? onMessage,
    void Function(String roomId)? onRoomRefresh,
  ) {
    _onWsMessage = onMessage;
    _onRoomRefresh = onRoomRefresh;
  }

  static void handleWsMessage(String roomId, Map<String, dynamic> payload) {
    _onWsMessage?.call(roomId, payload);
    _onRoomRefresh?.call(roomId);
  }
}

/// 将 emoji -> [userId] 转为 uid -> emoji（每个用户只保留一个表情）。
Map<String, String> _reactionsToKits(Map<String, List<String>> reactions) {
  final map = <String, String>{};
  for (final entry in reactions.entries) {
    for (final uid in entry.value) {
      if (uid.isNotEmpty) map[uid] = entry.key;
    }
  }
  return map;
}

/// 将服务端 [SnChatMessage] 转为 flutter_chat_kits [Message.parse] 所需的 Map。
Map<String, dynamic> snMessageToKitsMap(SnChatMessage sn) {
  final statuses = <String, String>{
    sn.senderId: 'sent',
  };
  return <String, dynamic>{
    'id': sn.id,
    'roomId': sn.roomId,
    'senderId': sn.senderId,
    'type': 'text',
    'content': sn.content,
    'statuses': statuses,
    'createdAt': sn.createdAt,
    'updatedAt': sn.updatedAt ?? sn.createdAt,
    'replyId': sn.replyMessage?.id ?? '',
    'reactions': _reactionsToKits(sn.reactions),
    'isDeleted': sn.deletedAt != null,
    'isEdited': false,
    'isForwarded': sn.forwardedMessage != null,
    'deletes': <String, bool>{},
    'pins': <String, bool>{},
    'removes': <String, bool>{},
  };
}

/// 将应用 [ChatRoom] 转为 flutter_chat_kits [Room.parse] 所需的 Map。
Map<String, dynamic> chatRoomToKitsMap(ChatRoom r) {
  final participants = r.members.map((m) => m.userId).where((id) => id.isNotEmpty).toSet().toList();
  return <String, dynamic>{
    'id': r.id,
    'isGroup': r.type == ChatRoomType.group,
    'name': r.name,
    'photo': r.avatarUrl,
    'participants': participants,
    'lastMessage': null,
    'lastMessageId': '',
    'lastMessageSenderId': '',
    'lastMessageDeleted': false,
    'lastMessageStatuses': <String, String>{},
    'unseenCount': <String, int>{MolianChatBackend.uid: 0},
    'updatedAt': r.lastMessageAt ?? r.createdAt ?? DateTime.now().toIso8601String(),
    'createdAt': r.createdAt ?? r.lastMessageAt,
    'createdBy': participants.isNotEmpty ? participants.first : '',
  };
}
