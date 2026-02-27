import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_provider.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_room_model.dart';
import '../data/models/sn_chat_message.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.read(dioProvider));
});

/// 当前用户的聊天房间列表。
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

  Future<ChatRoom> fetchOrCreateDirectRoom(String peerId) async {
    final dio = ref.read(dioProvider);
    final response = await dio.post<Map<String, dynamic>>(
      ApiConstants.messagerChatDirect(peerId),
    );
    final data = response.data;
    if (data == null) throw Exception('服务器返回空数据');
    final roomJson = (data['room'] as Map<String, dynamic>?) ?? data;
    final room = ChatRoom.fromJson(roomJson);
    final current = state.valueOrNull ?? [];
    if (!current.any((r) => r.id == room.id)) {
      state = AsyncData(<ChatRoom>[room, ...current]);
    }
    return room;
  }
}

/// 单个房间的消息状态：center 上方为更旧消息，下方为更新消息（双向列表不跳动）。
class RoomMessagesState {
  const RoomMessagesState({
    this.aboveCenter = const [],
    this.belowCenter = const [],
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  final List<SnChatMessage> aboveCenter;
  final List<SnChatMessage> belowCenter;
  final bool loading;
  final bool loadingMore;
  final String? error;

  List<SnChatMessage> get allInOrder {
    final list = <SnChatMessage>[...aboveCenter, ...belowCenter];
    list.sort((a, b) => _ts(a).compareTo(_ts(b)));
    return list;
  }

  int _ts(SnChatMessage m) {
    final s = m.createdAt;
    if (s == null || s.isEmpty) return 0;
    final dt = DateTime.tryParse(s);
    return dt?.millisecondsSinceEpoch ?? 0;
  }
}

class RoomMessagesNotifier extends FamilyNotifier<RoomMessagesState, String> {
  @override
  RoomMessagesState build(String roomId) => const RoomMessagesState();

  Future<void> loadInitial(String roomId) async {
    state = state.copyWith(loading: true, error: null);
    final repo = ref.read(chatRepositoryProvider);
    try {
      final list = await repo.fetchMessages(roomId, offset: 0, take: 50);
      state = RoomMessagesState(
        aboveCenter: [],
        belowCenter: list,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> loadMore(String roomId) async {
    if (state.loadingMore) return;
    final above = state.aboveCenter;
    final below = state.belowCenter;
    if (above.isEmpty && below.isEmpty) return;
    state = state.copyWith(loadingMore: true);
    final repo = ref.read(chatRepositoryProvider);
    try {
      final offset = above.length + below.length;
      final list = await repo.fetchMessages(roomId, offset: offset, take: 30);
      if (list.isEmpty) {
        state = state.copyWith(loadingMore: false);
        return;
      }
      final existingIds = {...above.map((m) => m.id), ...state.belowCenter.map((m) => m.id)};
      final newOlder = list.where((m) => !existingIds.contains(m.id)).toList();
      if (newOlder.isEmpty) {
        state = state.copyWith(loadingMore: false);
        return;
      }
      state = RoomMessagesState(
        aboveCenter: [...newOlder, ...above],
        belowCenter: state.belowCenter,
        loadingMore: false,
      );
    } catch (_) {
      state = state.copyWith(loadingMore: false);
    }
  }

  void appendMessage(String roomId, SnChatMessage message) {
    if (message.roomId != roomId) return;
    final below = List<SnChatMessage>.from(state.belowCenter);
    final idx = below.indexWhere((m) => m.id == message.id || m.nonce == message.nonce);
    if (idx >= 0) {
      below[idx] = message;
    } else {
      below.add(message);
      below.sort((a, b) => _ts(a).compareTo(_ts(b)));
    }
    state = state.copyWith(belowCenter: below);
  }

  void replaceOrAppendMessage(String roomId, SnChatMessage message) {
    if (message.roomId != roomId) return;
    final above = List<SnChatMessage>.from(state.aboveCenter);
    final below = List<SnChatMessage>.from(state.belowCenter);
    int i = above.indexWhere((m) => m.id == message.id);
    if (i >= 0) {
      above[i] = message;
      state = state.copyWith(aboveCenter: above);
      return;
    }
    i = below.indexWhere((m) => m.id == message.id);
    if (i >= 0) {
      below[i] = message;
      state = state.copyWith(belowCenter: below);
      return;
    }
    below.add(message);
    below.sort((a, b) => _ts(a).compareTo(_ts(b)));
    state = state.copyWith(belowCenter: below);
  }

  void markDeleted(String messageId) {
    SnChatMessage replace(SnChatMessage m) {
      if (m.id != messageId) return m;
      final j = Map<String, dynamic>.from(m.toJson());
      j['deleted_at'] = DateTime.now().toIso8601String();
      return SnChatMessage.fromJson(j);
    }
    state = state.copyWith(
      aboveCenter: state.aboveCenter.map(replace).toList(),
      belowCenter: state.belowCenter.map(replace).toList(),
    );
  }

  int _ts(SnChatMessage m) {
    final s = m.createdAt;
    if (s == null || s.isEmpty) return 0;
    final dt = DateTime.tryParse(s);
    return dt?.millisecondsSinceEpoch ?? 0;
  }
}

extension _RoomMessagesStateCopy on RoomMessagesState {
  RoomMessagesState copyWith({
    List<SnChatMessage>? aboveCenter,
    List<SnChatMessage>? belowCenter,
    bool? loading,
    bool? loadingMore,
    String? error,
  }) {
    return RoomMessagesState(
      aboveCenter: aboveCenter ?? this.aboveCenter,
      belowCenter: belowCenter ?? this.belowCenter,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: error ?? this.error,
    );
  }
}

/// 按房间 id 维度的消息列表状态（用于聊天室页）。
final roomMessagesProvider =
    NotifierProvider.family<RoomMessagesNotifier, RoomMessagesState, String>(
  RoomMessagesNotifier.new,
);
