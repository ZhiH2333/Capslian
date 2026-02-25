import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/api_constants.dart';
import '../../core/network/dio_provider.dart';
import '../data/chat_database.dart';
import '../data/models/local_chat_message.dart';
import '../data/models/sn_chat_message.dart';

/// 指定房间的消息列表状态管理。
final messagesProvider = AsyncNotifierProvider.family<MessagesNotifier,
    List<LocalChatMessage>, String>(
  MessagesNotifier.new,
);

class MessagesNotifier
    extends FamilyAsyncNotifier<List<LocalChatMessage>, String> {
  String get _roomId => arg;

  @override
  Future<List<LocalChatMessage>> build(String roomId) async {
    return _loadInitialMessages(forceRemoteRefresh: true);
  }

  Future<List<LocalChatMessage>> _loadInitialMessages({
    bool forceRemoteRefresh = false,
  }) async {
    final local = await ChatDatabase.getMessagesForRoom(_roomId);
    if (!forceRemoteRefresh) return local;
    try {
      final remote = await _fetchAndCacheMessages(offset: 0, take: 50);
      return remote;
    } catch (_) {
      return local;
    }
  }

  Future<List<LocalChatMessage>> _fetchAndCacheMessages({
    required int offset,
    required int take,
  }) async {
    final dio = ref.read(dioProvider);
    final response = await dio.get<Map<String, dynamic>>(
      ApiConstants.messagerChatMessages(_roomId),
      queryParameters: <String, dynamic>{'offset': offset, 'take': take},
    );
    final data = response.data;
    if (data == null) return [];
    final rawList = data['messages'] as List? ?? data['data'] as List? ?? [];
    final messages = rawList
        .map((dynamic e) => LocalChatMessage.fromRemoteMessage(
              SnChatMessage.fromJson(e as Map<String, dynamic>),
              MessageStatus.sent,
            ))
        .toList();
    await ChatDatabase.saveMessages(messages);
    return messages;
  }

  /// 重新从本地加载（供全局同步完成后调用）。
  Future<void> loadInitial({bool forceRemoteRefresh = false}) async {
    state = const AsyncLoading();
    state = AsyncData(
      await _loadInitialMessages(forceRemoteRefresh: forceRemoteRefresh),
    );
  }

  /// 分页拉取更早的消息。
  Future<void> fetchMoreMessages() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final offset = current.where((m) => !m.isPending).length;
    try {
      final older =
          await _fetchAndCacheMessages(offset: offset, take: 30);
      if (older.isEmpty) return;
      final existingIds = current.map((m) => m.id).toSet();
      final newOnes =
          older.where((m) => !existingIds.contains(m.id)).toList();
      if (newOnes.isEmpty) return;
      final merged = [...newOnes, ...current];
      merged.sort(_compareByCreatedAt);
      state = AsyncData(merged);
    } catch (_) {}
  }

  /// 发送消息（乐观更新 → 上传附件 → API → 替换为服务端消息）。
  Future<void> sendMessage(
    String content,
    List<SnChatAttachment> attachments, {
    LocalChatMessage? replyingTo,
    LocalChatMessage? editingTo,
    LocalChatMessage? forwardedFrom,
  }) async {
    final nonce = const Uuid().v4();
    final tempId = 'pending_$nonce';
    final now = DateTime.now().toIso8601String();
    final optimistic = LocalChatMessage(
      id: tempId,
      roomId: _roomId,
      senderId: '',
      content: content,
      status: MessageStatus.pending,
      createdAt: now,
      nonce: nonce,
      attachments: attachments,
      replyMessage: replyingTo,
      forwardedMessage: forwardedFrom,
    );
    await ChatDatabase.saveMessage(optimistic);
    final current = state.valueOrNull ?? [];
    state = AsyncData([...current, optimistic]);
    try {
      final dio = ref.read(dioProvider);
      final body = <String, dynamic>{
        'content': content,
        'nonce': nonce,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        if (replyingTo != null) 'reply_id': replyingTo.id,
        if (forwardedFrom != null) 'forwarded_id': forwardedFrom.id,
      };
      final method = editingTo == null ? 'POST' : 'PATCH';
      final path = editingTo == null
          ? ApiConstants.messagerChatMessages(_roomId)
          : ApiConstants.messagerChatMessage(_roomId, editingTo.id);
      final response = await dio.request<Map<String, dynamic>>(
        path,
        data: body,
        options: Options(method: method),
      );
      final raw = response.data;
      if (raw == null) throw Exception('发送失败：空响应');
      final serverRaw =
          (raw['message'] as Map<String, dynamic>?) ?? raw;
      final serverMessage = LocalChatMessage.fromRemoteMessage(
        SnChatMessage.fromJson(serverRaw),
        MessageStatus.sent,
      );
      await ChatDatabase.deleteMessage(tempId);
      await ChatDatabase.saveMessage(serverMessage);
      _replaceMessage(tempId, serverMessage);
    } catch (_) {
      await ChatDatabase.updateMessageStatus(tempId, MessageStatus.failed);
      _markFailed(tempId);
    }
  }

  /// 删除消息（软删除，向服务端发送 DELETE 请求）。
  Future<void> deleteMessage(String messageId) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.delete<void>(
        ApiConstants.messagerChatMessage(_roomId, messageId),
      );
      final current = state.valueOrNull ?? [];
      final updated = current.map((m) {
        if (m.id != messageId) return m;
        return m.copyWith(deletedAt: DateTime.now().toIso8601String());
      }).toList();
      state = AsyncData(updated);
    } catch (_) {}
  }

  /// 添加或移除表情反应。
  Future<void> toggleReaction(String messageId, String emoji) async {
    try {
      final dio = ref.read(dioProvider);
      final current = state.valueOrNull ?? [];
      final msg = current.firstWhere(
        (m) => m.id == messageId,
        orElse: () => throw Exception('消息不存在'),
      );
        const myId = '';
      final hasReacted = msg.reactions[emoji]?.contains(myId) ?? false;
      if (hasReacted) {
        await dio.delete<void>(
          ApiConstants.messagerChatMessageReaction(_roomId, messageId, emoji),
        );
      } else {
        await dio.put<void>(
          ApiConstants.messagerChatMessageReaction(_roomId, messageId, emoji),
        );
      }
    } catch (_) {}
  }

  /// WebSocket 收到新消息后调用，去重并写入 state。
  void receiveMessage(LocalChatMessage message) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.any((m) => m.id == message.id)) return;
    final next = [...current, message];
    next.sort(_compareByCreatedAt);
    state = AsyncData(next);
  }

  /// WebSocket 收到消息更新后调用。
  void receiveMessageUpdate(LocalChatMessage message) {
    final current = state.valueOrNull;
    if (current == null) return;
    final idx = current.indexWhere((m) => m.id == message.id);
    if (idx < 0) {
      receiveMessage(message);
      return;
    }
    final next = List<LocalChatMessage>.from(current);
    next[idx] = message;
    state = AsyncData(next);
  }

  /// WebSocket 收到消息删除后调用。
  void receiveMessageDeletion(String messageId) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current.map((m) {
      if (m.id != messageId) return m;
      return m.copyWith(deletedAt: DateTime.now().toIso8601String());
    }).toList();
    state = AsyncData(next);
  }

  void _replaceMessage(String oldId, LocalChatMessage newMessage) {
    final current = state.valueOrNull ?? [];
    final next = current
        .where((m) => m.id != oldId)
        .toList();
    next.add(newMessage);
    next.sort(_compareByCreatedAt);
    state = AsyncData(next);
  }

  void _markFailed(String tempId) {
    final current = state.valueOrNull ?? [];
    final next = current.map((m) {
      if (m.id != tempId) return m;
      return m.copyWith(status: MessageStatus.failed);
    }).toList();
    state = AsyncData(next);
  }
}

int _compareByCreatedAt(LocalChatMessage a, LocalChatMessage b) {
  final aTime = a.createdAt;
  final bTime = b.createdAt;
  if (aTime == null && bTime == null) return 0;
  if (aTime == null) return 1;
  if (bTime == null) return -1;
  return aTime.compareTo(bTime);
}
