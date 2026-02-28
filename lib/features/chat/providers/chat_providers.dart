import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_provider.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_room_model.dart';

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
    if (!current.any((ChatRoom r) => r.id == room.id)) {
      state = AsyncData(<ChatRoom>[room, ...current]);
    }
    return room;
  }
}
