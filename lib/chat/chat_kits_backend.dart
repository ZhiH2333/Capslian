import 'package:dio/dio.dart';
import 'package:flutter_chat_kits/flutter_chat_kits.dart';

import '../core/constants/api_constants.dart';
import 'data/models/chat_room_model.dart';
import 'data/models/sn_chat_message.dart';

/// 将可能为相对路径的图片 URL 转为绝对 URL，避免 CachedNetworkImage 加载失败。
/// 供聊天图片气泡、消息解析等统一使用。
String toAbsoluteImageUrl(String url) {
  if (url.isEmpty) return url;
  final u = url.trim();
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  final base = ApiConstants.baseUrl;
  final path = u.startsWith('/') ? u : '/$u';
  return base.endsWith('/') ? '$base${path.substring(1)}' : '$base$path';
}

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

/// 将服务端日期时间字符串规范为 ISO8601，便于正确解析与显示（避免 00:00）。
/// 例如 "2026-02-27 13:16:31" → "2026-02-27T13:16:31Z"（按 UTC 解析后 toLocal 显示正确）。
String? _normalizeCreatedAt(String? raw) {
  if (raw == null || raw.trim().isEmpty) return raw;
  final s = raw.trim();
  if (s.contains('Z') || s.contains('+')) return s;
  final spaceIdx = s.indexOf(' ');
  if (spaceIdx <= 0) return s;
  final withT = '${s.substring(0, spaceIdx)}T${s.substring(spaceIdx + 1)}';
  return withT.endsWith('Z') ? withT : '$withT${withT.contains('.') ? '' : '.000'}Z';
}

/// 解析为毫秒时间戳（供 flutter_chat_kits Message.parse 的 createdAt 使用，key 为 'createdAt'）。
/// 若为仅日期格式（无时分）或解析结果为本地 00:00，则视为服务端未返回真实时间，改用当前时间避免整屏 00:00。
int? _createdAtToMilliseconds(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final s = raw.trim();
  if (s.length <= 10 && !s.contains('T') && !s.contains(' ')) return DateTime.now().millisecondsSinceEpoch;
  final normalized = _normalizeCreatedAt(raw);
  if (normalized == null) return null;
  final dt = DateTime.tryParse(normalized);
  if (dt == null) return null;
  final local = dt.toLocal();
  final isMidnight = local.hour == 0 && local.minute == 0;
  if (isMidnight) return DateTime.now().millisecondsSinceEpoch;
  return dt.millisecondsSinceEpoch;
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
  final imageUrls = sn.attachments
      .where((a) => a.isImage && a.url.isNotEmpty)
      .map((a) => toAbsoluteImageUrl(a.url))
      .toList();
  final isImage = imageUrls.isNotEmpty;
  final statuses = <String, String>{
    sn.senderId: 'sent',
  };
  final createdAtMs = _createdAtToMilliseconds(sn.createdAt);
  final updatedAtMs = _createdAtToMilliseconds(sn.updatedAt ?? sn.createdAt);
  return <String, dynamic>{
    'id': sn.id,
    'roomId': sn.roomId,
    'senderId': sn.senderId,
    'type': isImage ? 'image' : 'text',
    'content': sn.content,
    if (isImage) 'urls': imageUrls,
    'statuses': statuses,
    'createdAt': createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
    'updatedAt': updatedAtMs ?? createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
    'created_at': _normalizeCreatedAt(sn.createdAt),
    'updated_at': _normalizeCreatedAt(sn.updatedAt ?? sn.createdAt),
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
/// [directPeerId] 用于私信房间且服务端未返回 members 时，显式指定对方用户 id。
Map<String, dynamic> chatRoomToKitsMap(ChatRoom r, {String? directPeerId}) {
  List<String> participants = r.members.map((m) => m.userId).where((id) => id.isNotEmpty).toSet().toList();
  if (participants.isEmpty && r.isDirect && directPeerId != null && directPeerId.isNotEmpty) {
    participants = [directPeerId];
  }
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
    'extra': <String, dynamic>{'roomName': r.name},
  };
}
