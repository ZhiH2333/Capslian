import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_constants.dart';
import '../../core/network/dio_provider.dart';
import '../data/models/chat_room_model.dart';

/// 当前用户所在的聊天房间列表（供好友 Tab 创建私信房间等使用）。
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
    final current = state.valueOrNull ?? [];
    if (!current.any((r) => r.id == room.id)) {
      state = AsyncData(<ChatRoom>[room, ...current]);
    }
    return room;
  }
}
