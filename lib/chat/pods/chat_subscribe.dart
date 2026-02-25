import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/direct/providers/chat_providers.dart';
import '../events/chat_events.dart';
import 'messages_notifier.dart';

/// 订阅指定聊天房间的实时消息。
/// 进入聊天页时 watch 此 provider，离开时自动取消订阅。
/// 内部：
///   创建时 → 发送 messages.subscribe WebSocket 消息
///   销毁时 → 发送 messages.unsubscribe WebSocket 消息
///   监听 EventBus → 转发到对应 MessagesNotifier
final chatSubscribeProvider =
    Provider.autoDispose.family<void, String>((ref, roomId) {
  final ws = ref.read(webSocketServiceProvider);
  ws.send(<String, dynamic>{
    'type': 'messages.subscribe',
    'chat_room_id': roomId,
  });

  final notifier = ref.read(messagesProvider(roomId).notifier);

  final subscriptions = <StreamSubscription<dynamic>>[
    chatEventBus.on<ChatMessageNewEvent>().listen((ChatMessageNewEvent event) {
      if (event.message.roomId != roomId) return;
      notifier.receiveMessage(event.message);
    }),
    chatEventBus
        .on<ChatMessageUpdateEvent>()
        .listen((ChatMessageUpdateEvent event) {
      if (event.message.roomId != roomId) return;
      notifier.receiveMessageUpdate(event.message);
    }),
    chatEventBus
        .on<ChatMessageDeleteEvent>()
        .listen((ChatMessageDeleteEvent event) {
      if (event.roomId != roomId) return;
      notifier.receiveMessageDeletion(event.messageId);
    }),
    chatEventBus
        .on<ChatMessagesSyncedEvent>()
        .listen((ChatMessagesSyncedEvent event) {
      if (event.roomId != roomId) return;
      notifier.loadInitial(forceRemoteRefresh: false);
    }),
  ];

  ref.onDispose(() {
    ws.send(<String, dynamic>{
      'type': 'messages.unsubscribe',
      'chat_room_id': roomId,
    });
    for (final sub in subscriptions) {
      sub.cancel();
    }
  });
});

/// 当前正在输入的用户 ID 集合（按房间）的通知器。
class _TypingUsersNotifier extends AutoDisposeFamilyNotifier<Set<String>, String> {
  final Map<String, Timer> _timers = {};
  StreamSubscription<ChatTypingEvent>? _sub;

  @override
  Set<String> build(String arg) {
    _sub = chatEventBus.on<ChatTypingEvent>().listen(_onTyping);
    ref.onDispose(() {
      _sub?.cancel();
      for (final t in _timers.values) {
        t.cancel();
      }
    });
    return {};
  }

  void _onTyping(ChatTypingEvent event) {
    if (event.roomId != arg) return;
    if (event.isTyping) {
      state = {...state, event.userId};
      _timers[event.userId]?.cancel();
      _timers[event.userId] = Timer(const Duration(seconds: 5), () {
        state = state.difference({event.userId});
        _timers.remove(event.userId);
      });
    } else {
      _timers[event.userId]?.cancel();
      _timers.remove(event.userId);
      state = state.difference({event.userId});
    }
  }
}

/// 当前正在输入的用户 ID 集合（按房间）。
final typingUsersProvider =
    NotifierProvider.autoDispose.family<_TypingUsersNotifier, Set<String>, String>(
  _TypingUsersNotifier.new,
);
