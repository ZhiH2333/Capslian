import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/storage_providers.dart';
import '../../../core/network/websocket_service.dart';
import '../data/chat_local_dao.dart';
import '../data/models/message_model.dart';
import '../../auth/providers/auth_providers.dart';
import '../../social/providers/social_providers.dart';

/// WebSocket 服务单例：连接管理、重连、心跳；登出时自动断开。
final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final getToken = () => ref.read(tokenStorageProvider).getToken();
  final service = WebSocketService(getToken: getToken);
  ref.onDispose(() => service.dispose());
  return service;
});

/// 登录后仅断开时清理 WebSocket；连接推迟到用户打开聊天 Tab 时再执行，避免启动时连接被拒导致未处理异常。
final wsLifecycleProvider = Provider<void>((ref) {
  ref.listen(authStateProvider, (Object? prev, AsyncValue<dynamic> next) {
    next.whenData((dynamic user) {
      final ws = ref.read(webSocketServiceProvider);
      if (user == null) {
        ws.disconnect();
      }
      // 不再在登录时自动 connect，改为在进入聊天 Tab 时连接（见 wsConnectWhenEnteringChatProvider）
    });
  });
});

/// 当前 WebSocket 连接状态。
final wsConnectionStateProvider = StreamProvider<WsConnectionState>((ref) {
  final service = ref.watch(webSocketServiceProvider);
  return service.connectionState;
});

/// 服务端通过 WebSocket 下发的原始消息（type / message 等）。
final wsRawMessagesProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final service = ref.watch(webSocketServiceProvider);
  return service.messages;
});

/// 与指定用户的聊天消息列表（REST 初载 + 内存追加 WebSocket 新消息）。
/// 使用 [chatMessagesNotifierProvider(peerUserId)] 获取列表并调用 notifier 追加/更新。
final chatMessagesNotifierProvider =
    AsyncNotifierProvider.family<ChatMessagesNotifier, List<MessageModel>, String>(
        ChatMessagesNotifier.new);

class ChatMessagesNotifier extends FamilyAsyncNotifier<List<MessageModel>, String> {
  @override
  Future<List<MessageModel>> build(String peerUserId) async {
    if (peerUserId.isEmpty) return [];
    final me = ref.read(authStateProvider).valueOrNull;
    if (me == null) return [];
    final myId = me.id;
    List<MessageModel> list = await ChatLocalDao.getMessages(myId: myId, peerId: peerUserId);
    try {
      final repo = ref.read(socialRepositoryProvider);
      final raw = await repo.getMessages(peerUserId, limit: 50);
      final serverList = raw.map((e) => MessageModel.fromJson(e)).toList();
      final merged = _mergeMessages(list, serverList);
      merged.sort((a, b) => _compareCreatedAt(a.createdAt, b.createdAt));
      await ChatLocalDao.insertOrReplaceAll(
        merged.map((m) => <String, dynamic>{
              'id': m.id,
              'sender_id': m.senderId,
              'receiver_id': m.receiverId,
              'content': m.content,
              'created_at': m.createdAt,
              'read': m.read ? 1 : 0,
            }).toList(),
      );
      return merged;
    } catch (_) {
      return list;
    }
  }

  List<MessageModel> _mergeMessages(List<MessageModel> local, List<MessageModel> server) {
    final byId = <String, MessageModel>{};
    for (final m in local) byId[m.id] = m;
    for (final m in server) byId[m.id] = m;
    return byId.values.toList();
  }

  void _saveToLocal(MessageModel message) {
    ChatLocalDao.insertOrReplace(<String, dynamic>{
      'id': message.id,
      'sender_id': message.senderId,
      'receiver_id': message.receiverId,
      'content': message.content,
      'created_at': message.createdAt,
      'read': message.read ? 1 : 0,
    });
  }

  /// 从 WebSocket 收到新消息时追加（去重）并落库。
  void appendFromWs(MessageModel message) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.any((m) => m.id == message.id)) return;
    _saveToLocal(message);
    final next = List<MessageModel>.from(current)..add(message);
    next.sort((a, b) => _compareCreatedAt(a.createdAt, b.createdAt));
    state = AsyncData(next);
  }

  /// 乐观追加一条（发送中），返回临时 id 用于后续替换；写入本地以便离线可见。
  void appendOptimistic(MessageModel message) {
    final current = state.valueOrNull;
    if (current == null) return;
    _saveToLocal(message);
    final next = List<MessageModel>.from(current)..add(message);
    next.sort((a, b) => _compareCreatedAt(a.createdAt, b.createdAt));
    state = AsyncData(next);
  }

  /// 按 id 替换或追加一条（发送成功/服务端回包）并落库。
  void replaceOrAppend(MessageModel message) {
    final current = state.valueOrNull;
    if (current == null) return;
    _saveToLocal(message);
    final idx = current.indexWhere((m) => m.id == message.id);
    final next = List<MessageModel>.from(current);
    if (idx >= 0) {
      next[idx] = message;
    } else {
      next.add(message);
      next.sort((a, b) => _compareCreatedAt(a.createdAt, b.createdAt));
    }
    state = AsyncData(next);
  }

  /// 将指定临时 id 的消息标记为发送失败。
  void markFailed(String temporaryId) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current.map((m) {
      if (m.id == temporaryId) return m.copyWith(status: MessageStatus.failed);
      return m;
    }).toList();
    state = AsyncData(next);
  }

  /// 加载更早的消息（分页）；cursor 为当前列表最早一条的 created_at。
  Future<void> loadOlder(String peerUserId, String? cursor) async {
    if (cursor == null || cursor.isEmpty) return;
    final me = ref.read(authStateProvider).valueOrNull;
    if (me == null) return;
    final current = state.valueOrNull;
    if (current == null) return;
    try {
      final repo = ref.read(socialRepositoryProvider);
      final raw = await repo.getMessages(peerUserId, cursor: cursor, limit: 20);
      if (raw.isEmpty) return;
      final older = raw.map((e) => MessageModel.fromJson(e)).toList();
      final existingIds = current.map((m) => m.id).toSet();
      final newOnes = older.where((m) => !existingIds.contains(m.id)).toList();
      if (newOnes.isEmpty) return;
      await ChatLocalDao.insertOrReplaceAll(
        newOnes.map((m) => <String, dynamic>{
              'id': m.id,
              'sender_id': m.senderId,
              'receiver_id': m.receiverId,
              'content': m.content,
              'created_at': m.createdAt,
              'read': m.read ? 1 : 0,
            }).toList(),
      );
      final next = List<MessageModel>.from(newOnes)..addAll(current);
      next.sort((a, b) => _compareCreatedAt(a.createdAt, b.createdAt));
      state = AsyncData(next);
    } catch (_) {}
  }
}

int _compareCreatedAt(String? a, String? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  return a.compareTo(b);
}
