import 'package:event_bus/event_bus.dart';

import '../data/models/local_chat_message.dart';

/// 全局聊天 EventBus 单例，用于组件间解耦通信。
final EventBus chatEventBus = EventBus();

/// 收到新消息时触发。
class ChatMessageNewEvent {
  const ChatMessageNewEvent(this.message);
  final LocalChatMessage message;
}

/// 消息更新时触发（编辑、反应变更等）。
class ChatMessageUpdateEvent {
  const ChatMessageUpdateEvent(this.message);
  final LocalChatMessage message;
}

/// 消息删除时触发。
class ChatMessageDeleteEvent {
  const ChatMessageDeleteEvent({
    required this.messageId,
    required this.roomId,
  });
  final String messageId;
  final String roomId;
}

/// 收到输入状态时触发。
class ChatTypingEvent {
  const ChatTypingEvent({
    required this.roomId,
    required this.userId,
    required this.isTyping,
  });
  final String roomId;
  final String userId;
  final bool isTyping;
}

/// 房间消息全量同步完成时触发。
class ChatMessagesSyncedEvent {
  const ChatMessagesSyncedEvent(this.roomId);
  final String roomId;
}
