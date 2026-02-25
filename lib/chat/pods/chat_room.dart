import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_constants.dart';
import '../../core/network/dio_provider.dart';
import '../../features/direct/providers/chat_providers.dart';
import '../data/chat_database.dart';
import '../data/models/chat_room_model.dart';
import '../data/models/local_chat_message.dart';
import '../data/models/sn_chat_message.dart';
import '../events/chat_events.dart';

/// 某个房间的最新一条消息（仅查本地 DB，供会话列表预览使用）。
final roomLastMessageProvider =
    AutoDisposeFutureProvider.family<LocalChatMessage?, String>((ref, roomId) async {
  return ChatDatabase.getLastMessageForRoom(roomId);
});

/// 当前用户所在的聊天房间列表。
final chatRoomListProvider =
    AsyncNotifierProvider<ChatRoomListNotifier, List<ChatRoom>>(
  ChatRoomListNotifier.new,
);

class ChatRoomListNotifier extends AsyncNotifier<List<ChatRoom>> {
  @override
  Future<List<ChatRoom>> build() async {
    return fetchRooms();
  }

  Future<List<ChatRoom>> fetchRooms() async {
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get<Map<String, dynamic>>(
        ApiConstants.messagerChat,
      );
      final data = response.data;
      if (data == null) return [];
      final rawList =
          data['rooms'] as List? ?? data['data'] as List? ?? [];
      return rawList
          .map((dynamic e) =>
              ChatRoom.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 获取或创建与某用户的私信房间。
  /// 失败时抛出 [Exception]，调用方负责处理错误提示。
  Future<ChatRoom> fetchOrCreateDirectRoom(String peerId) async {
    final dio = ref.read(dioProvider);
    final response = await dio.post<Map<String, dynamic>>(
      ApiConstants.messagerChatDirect(peerId),
    );
    final data = response.data;
    if (data == null) throw Exception('服务器返回空数据');
    final roomJson = (data['room'] as Map<String, dynamic>?) ?? data;
    final room = ChatRoom.fromJson(roomJson);
    // 若房间不在当前列表中，将其插入顶部（无需重新请求列表）
    final current = state.valueOrNull ?? [];
    if (!current.any((r) => r.id == room.id)) {
      state = AsyncData(<ChatRoom>[room, ...current]);
    }
    return room;
  }

  /// 收到新消息时，将对应房间移到列表顶部（体现"最近活跃"排序）。
  /// 若房间不在列表中则触发一次完整刷新。
  void handleNewMessage(String roomId) {
    final current = state.valueOrNull;
    if (current == null) return;
    final idx = current.indexWhere((r) => r.id == roomId);
    if (idx < 0) {
      fetchRooms();
      return;
    }
    final room = current[idx];
    final next = List<ChatRoom>.from(current)
      ..removeAt(idx)
      ..insert(0, room);
    state = AsyncData(next);
  }
}

/// 全局 WebSocket 消息监听与处理，写入本地 DB 并发布 EventBus 事件。
/// 在 main.dart 中通过 ref.watch(chatGlobalSyncProvider) 激活。
final chatGlobalSyncProvider =
    NotifierProvider<ChatGlobalSyncNotifier, void>(
  ChatGlobalSyncNotifier.new,
);

class ChatGlobalSyncNotifier extends Notifier<void> {
  @override
  void build() {
    _startWebSocketListener();
  }

  void _startWebSocketListener() {
    ref.listen(wsRawMessagesProvider, (_, AsyncValue<Map<String, dynamic>> next) {
      next.whenData(_handleWebSocketMessage);
    });
  }

  Future<void> _handleWebSocketMessage(Map<String, dynamic> payload) async {
    final type = payload['type'] as String?;
    if (type == null) return;
    switch (type) {
      case 'messages.new':
        await _handleNewMessage(payload);
      case 'messages.update':
      case 'messages.update.links':
        await _handleUpdateMessage(payload);
      case 'messages.delete':
        await _handleDeleteMessage(payload);
      case 'messages.reaction.added':
        await _handleReactionAdded(payload);
      case 'messages.reaction.removed':
        await _handleReactionRemoved(payload);
      case 'messages.typing':
        _handleTyping(payload);
    }
  }

  Future<void> _handleNewMessage(Map<String, dynamic> payload) async {
    final msgJson = payload['message'] as Map<String, dynamic>? ?? payload;
    try {
      final remote = SnChatMessage.fromJson(msgJson);
      final local = LocalChatMessage.fromRemoteMessage(
        remote,
        MessageStatus.sent,
      );
      await ChatDatabase.saveMessage(local);
      chatEventBus.fire(ChatMessageNewEvent(local));
      if (local.roomId.isNotEmpty) {
        ref.read(chatRoomListProvider.notifier).handleNewMessage(local.roomId);
        ref.invalidate(roomLastMessageProvider(local.roomId));
      }
    } catch (_) {}
  }

  Future<void> _handleUpdateMessage(Map<String, dynamic> payload) async {
    final msgJson = payload['message'] as Map<String, dynamic>? ?? payload;
    try {
      final remote = SnChatMessage.fromJson(msgJson);
      final existing = await ChatDatabase.getMessageById(remote.id);
      final local = LocalChatMessage.fromRemoteMessage(
        remote,
        existing?.status ?? MessageStatus.sent,
      );
      await ChatDatabase.saveMessage(local);
      chatEventBus.fire(ChatMessageUpdateEvent(local));
    } catch (_) {}
  }

  Future<void> _handleDeleteMessage(Map<String, dynamic> payload) async {
    final messageId = (payload['message_id'] as Object?)?.toString() ??
        (payload['id'] as Object?)?.toString() ??
        '';
    final roomId = (payload['room_id'] as Object?)?.toString() ??
        (payload['chat_room_id'] as Object?)?.toString() ??
        '';
    if (messageId.isEmpty) return;
    final existing = await ChatDatabase.getMessageById(messageId);
    if (existing != null) {
      final deleted = existing.copyWith(
        deletedAt: DateTime.now().toIso8601String(),
      );
      await ChatDatabase.saveMessage(deleted);
    }
    chatEventBus.fire(
      ChatMessageDeleteEvent(messageId: messageId, roomId: roomId),
    );
  }

  Future<void> _handleReactionAdded(Map<String, dynamic> payload) async {
    await _updateReaction(payload, add: true);
  }

  Future<void> _handleReactionRemoved(Map<String, dynamic> payload) async {
    await _updateReaction(payload, add: false);
  }

  Future<void> _updateReaction(
    Map<String, dynamic> payload, {
    required bool add,
  }) async {
    final messageId = (payload['message_id'] as Object?)?.toString() ?? '';
    final emoji = (payload['emoji'] as Object?)?.toString() ?? '';
    final userId = (payload['user_id'] as Object?)?.toString() ?? '';
    if (messageId.isEmpty || emoji.isEmpty || userId.isEmpty) return;
    final existing = await ChatDatabase.getMessageById(messageId);
    if (existing == null) return;
    final reactions =
        Map<String, List<String>>.from(existing.reactions.map(
      (k, v) => MapEntry(k, List<String>.from(v)),
    ));
    if (add) {
      reactions.putIfAbsent(emoji, () => []);
      if (!reactions[emoji]!.contains(userId)) {
        reactions[emoji]!.add(userId);
      }
    } else {
      reactions[emoji]?.remove(userId);
      if (reactions[emoji]?.isEmpty == true) reactions.remove(emoji);
    }
    final updated = existing.copyWith(reactions: reactions);
    await ChatDatabase.saveMessage(updated);
    chatEventBus.fire(ChatMessageUpdateEvent(updated));
  }

  void _handleTyping(Map<String, dynamic> payload) {
    final roomId = (payload['room_id'] as Object?)?.toString() ??
        (payload['chat_room_id'] as Object?)?.toString() ??
        '';
    final userId = (payload['user_id'] as Object?)?.toString() ?? '';
    if (roomId.isEmpty || userId.isEmpty) return;
    chatEventBus.fire(
      ChatTypingEvent(
        roomId: roomId,
        userId: userId,
        isTyping: payload['is_typing'] as bool? ?? true,
      ),
    );
  }

  /// 全量同步所有房间的最新消息（仅刷新各 MessagesNotifier 本地缓存）。
  void syncAllMessages(List<String> roomIds) {
    for (final roomId in roomIds) {
      chatEventBus.fire(ChatMessagesSyncedEvent(roomId));
    }
  }
}
