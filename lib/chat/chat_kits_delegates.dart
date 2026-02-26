import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_chat_kits/flutter_chat_kits.dart';

import 'chat_kits_backend.dart';
import '../core/constants/api_constants.dart';
import 'data/models/chat_room_model.dart';
import 'data/models/sn_chat_message.dart';

/// 消息 delegate：REST 收发 + 内存流 + WebSocket 由外部注入事件。
class MolianChatMessageDelegate implements ChatMessageDelegate {
  MolianChatMessageDelegate(this._messageStreams);

  final Map<String, StreamController<List<Message>>> _messageStreams;
  final Map<String, List<Message>> _cache = {};

  Dio? get _dio => MolianChatBackend.dio;

  Future<List<Message>> _fetchMessages(String roomId) async {
    final dio = _dio;
    if (dio == null) return [];
    try {
      final res = await dio.get<Map<String, dynamic>>(
        ApiConstants.messagerChatMessages(roomId),
        queryParameters: <String, dynamic>{'offset': 0, 'take': 50},
      );
      final data = res.data;
      if (data == null) return [];
      final raw = data['messages'] as List? ?? data['data'] as List? ?? [];
      return raw
          .map((e) => Message.parse(snMessageToKitsMap(
              SnChatMessage.fromJson(e as Map<String, dynamic>))))
          .where((m) => !m.isEmpty)
          .toList()
        ..sort((a, b) => a.createdAt.timestamp.compareTo(b.createdAt.timestamp));
    } catch (_) {
      return [];
    }
  }

  void appendOrUpdateMessage(String roomId, Message msg) {
    _cache[roomId] ??= [];
    final list = _cache[roomId]!;
    final idx = list.indexWhere((m) => m.id == msg.id);
    if (idx >= 0) {
      list[idx] = msg;
    } else {
      list.add(msg);
      list.sort((a, b) => a.createdAt.timestamp.compareTo(b.createdAt.timestamp));
    }
    _messageStreams[roomId]?.add(List.from(list));
  }

  void removeOrMarkDeleted(String roomId, String messageId) {
    final list = _cache[roomId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      list[idx] = list[idx].copyWith(isDeleted: true);
      _messageStreams[roomId]?.add(List.from(list));
    }
  }

  @override
  Future<void> create(String roomId, String msgId, Map<String, dynamic> value) async {
    final dio = _dio;
    if (dio == null) return;
    final content = value['content'] as String? ?? value['text'] as String? ?? '';
    final body = <String, dynamic>{
      'content': content,
      'nonce': msgId,
      if (value['replyId'] != null && (value['replyId'] as String).isNotEmpty)
        'reply_id': value['replyId'],
    };
    await dio.post<Map<String, dynamic>>(
      ApiConstants.messagerChatMessages(roomId),
      data: body,
    );
  }

  @override
  Future<void> update(String roomId, String id, Map<String, dynamic> value) async {
    final dio = _dio;
    if (dio == null) return;
    final content = value['content'] as String? ?? value['text'] as String? ?? '';
    await dio.patch<Map<String, dynamic>>(
      ApiConstants.messagerChatMessage(roomId, id),
      data: <String, dynamic>{'content': content},
    );
  }

  @override
  Future<void> delete(String roomId, String id) async {
    final dio = _dio;
    if (dio == null) return;
    await dio.delete<void>(ApiConstants.messagerChatMessage(roomId, id));
  }

  @override
  Future<void> deletes(Iterable<Message> messages) async {
    for (final m in messages) {
      await delete(m.roomId, m.id);
    }
  }

  @override
  Future<void> deleteAll(String roomId) async {
    final dio = _dio;
    if (dio == null) return;
    final list = await dio.get<Map<String, dynamic>>(
      ApiConstants.messagerChatMessages(roomId),
      queryParameters: <String, dynamic>{'take': 1000},
    );
    final messages = list.data?['messages'] as List? ?? list.data?['data'] as List? ?? [];
    for (final m in messages) {
      final id = (m is Map ? m['id'] : null)?.toString();
      if (id != null && id.isNotEmpty) await delete(roomId, id);
    }
  }

  @override
  Future<void> updates(String roomId, Map<String, Map<String, dynamic>> values) async {
    for (final e in values.entries) {
      await update(roomId, e.key, e.value);
    }
  }

  @override
  Future<String> upload(MessageUploadData data) async {
    final dio = _dio;
    if (dio == null) return '';
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(data.path, filename: data.name),
      });
      final res = await dio.post<Map<String, dynamic>>(
        ApiConstants.upload,
        data: formData,
      );
      final url = res.data?['url'] as String? ?? res.data?['path'] as String? ?? '';
      return url.isNotEmpty ? '${ApiConstants.baseUrl}$url' : '';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<void> deleteFromStorage(String url) async {}

  @override
  Stream<List<Message>> stream(String roomId) async* {
    _messageStreams[roomId] ??= StreamController<List<Message>>.broadcast();
    if (_cache[roomId] == null) {
      _cache[roomId] = await _fetchMessages(roomId);
      _messageStreams[roomId]!.add(_cache[roomId]!);
    }
    yield _cache[roomId]!;
    await for (final next in _messageStreams[roomId]!.stream) {
      yield next;
    }
  }
}

/// 房间 delegate：拉取列表 + 单房间获取；流由 controller 推送。
class MolianChatRoomDelegate implements ChatRoomDelegate {
  MolianChatRoomDelegate(this._roomController);

  final StreamController<bool> _roomController;

  Dio? get _dio => MolianChatBackend.dio;

  @override
  Future<void> create(String roomId, Map<String, dynamic> value) async {
    final participants = value['participants'] as List?;
    if (participants == null || participants.length < 2) return;
    final friendId = participants
        .where((e) => e != MolianChatBackend.uid)
        .cast<String>()
        .firstOrNull;
    if (friendId == null) return;
    final dio = _dio;
    if (dio == null) return;
    await dio.post<Map<String, dynamic>>(
      ApiConstants.messagerChatDirect(friendId),
    );
  }

  @override
  Future<Room> get(String roomId) async {
    final list = await _fetchRooms();
    final r = list.where((r) => r.id == roomId).firstOrNull;
    if (r != null) return r;
    return Room.empty();
  }

  Future<List<Room>> _fetchRooms() async {
    final dio = _dio;
    if (dio == null) return [];
    try {
      final res = await dio.get<Map<String, dynamic>>(ApiConstants.messagerChat);
      final data = res.data;
      if (data == null) return [];
      final raw = data['rooms'] as List? ?? data['data'] as List? ?? [];
      return raw
          .map((e) => Room.parse(chatRoomToKitsMap(ChatRoom.fromJson(e as Map<String, dynamic>))))
          .where((r) => !r.isEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> update(String roomId, Map<String, dynamic> value) async {}

  @override
  Future<void> delete(String roomId) async {}

  @override
  Stream<List<Room>> stream(String uid) async* {
    if (uid.isEmpty) return;
    yield await _fetchRooms();
    await for (final _ in _roomController.stream) {
      yield await _fetchRooms();
    }
  }

  void refreshRooms() {
    _roomController.add(true);
  }
}

/// 资料 delegate：仅占位，可后续接用户 API。
class MolianChatProfileDelegate implements ChatProfileDelegate {
  @override
  Future<void> update(String uid, Map<String, dynamic> value) async {}

  @override
  Stream<Profile> stream(String uid) => Stream.value(Profile.empty());
}

/// 状态 delegate：占位。
class MolianChatStatusDelegate implements ChatStatusDelegate {
  @override
  Future<void> online(String uid, Map<String, dynamic> value) async {}

  @override
  Future<void> offline(String uid, Map<String, dynamic> value) async {}

  @override
  Stream<Status> stream(String uid) => Stream.value(Status.empty());
}

/// 输入状态 delegate：占位（可后续接 WebSocket typing 事件）。
class MolianChatTypingDelegate implements ChatTypingDelegate {
  @override
  Future<void> start(String roomId, String uid) async {}

  @override
  Future<void> end(String uid) async {}

  @override
  Stream<Typing> stream(String uid) => Stream.value(Typing.empty());
}

/// 推送通知 delegate：占位。
class MolianChatNotificationDelegate implements ChatNotificationDelegate {
  @override
  Future<String?> deviceToken() async => null;

  @override
  Future<void> send(ChatNotificationContent content) async {}
}

/// 时间戳与字段规范化。
class MolianChatNormalizer extends ChatFieldValueNormalizer {
  @override
  ChatValueTimestamp timestamp(Object? raw) {
    if (raw == null) return const ChatValueTimestamp();
    if (raw is DateTime) return ChatValueTimestamp.fromDateTime(raw);
    if (raw is String) {
      final dt = DateTime.tryParse(raw);
      if (dt != null) return ChatValueTimestamp.fromDateTime(dt);
    }
    if (raw is num && raw > 0) {
      return ChatValueTimestamp.fromDateTime(
        DateTime.fromMillisecondsSinceEpoch(raw.toInt()),
      );
    }
    return const ChatValueTimestamp();
  }

  @override
  Object? message(Object? raw) => raw;

  @override
  Object? profile(Object? raw) => raw;

  @override
  Object? room(Object? raw) => raw;

  @override
  Object? status(Object? raw) => raw;

  @override
  Object? typing(Object? raw) => raw;
}
