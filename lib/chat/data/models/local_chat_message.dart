import 'dart:convert';

import 'sn_chat_message.dart';

/// 本地消息状态。
enum MessageStatus {
  pending,
  sent,
  failed,
}

/// 本地存储与 UI 渲染用的聊天消息。
class LocalChatMessage {
  const LocalChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.content,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.nonce,
    this.attachments = const [],
    this.replyMessage,
    this.forwardedMessage,
    this.reactions = const {},
    this.meta,
    this.sender,
  });

  final String id;
  final String roomId;
  final String senderId;
  final String content;
  final MessageStatus status;
  final String? createdAt;
  final String? updatedAt;
  final String? deletedAt;
  final String? nonce;
  final List<SnChatAttachment> attachments;
  final LocalChatMessage? replyMessage;
  final LocalChatMessage? forwardedMessage;
  final Map<String, List<String>> reactions;
  final Map<String, dynamic>? meta;
  final SnChatSender? sender;

  bool get isPending => status == MessageStatus.pending;
  bool get isFailed => status == MessageStatus.failed;
  bool get isDeleted => deletedAt != null;

  static LocalChatMessage fromRemoteMessage(
    SnChatMessage remote,
    MessageStatus messageStatus,
  ) {
    return LocalChatMessage(
      id: remote.id,
      roomId: remote.roomId,
      senderId: remote.senderId,
      content: remote.content,
      status: messageStatus,
      createdAt: remote.createdAt,
      updatedAt: remote.updatedAt,
      deletedAt: remote.deletedAt,
      nonce: remote.nonce,
      attachments: remote.attachments,
      replyMessage: remote.replyMessage != null
          ? LocalChatMessage.fromRemoteMessage(
              remote.replyMessage!, MessageStatus.sent)
          : null,
      forwardedMessage: remote.forwardedMessage != null
          ? LocalChatMessage.fromRemoteMessage(
              remote.forwardedMessage!, MessageStatus.sent)
          : null,
      reactions: remote.reactions,
      meta: remote.meta,
      sender: remote.sender,
    );
  }

  LocalChatMessage copyWith({
    String? id,
    String? roomId,
    String? senderId,
    String? content,
    MessageStatus? status,
    String? createdAt,
    String? updatedAt,
    String? deletedAt,
    String? nonce,
    List<SnChatAttachment>? attachments,
    LocalChatMessage? replyMessage,
    LocalChatMessage? forwardedMessage,
    Map<String, List<String>>? reactions,
    Map<String, dynamic>? meta,
    SnChatSender? sender,
  }) {
    return LocalChatMessage(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      nonce: nonce ?? this.nonce,
      attachments: attachments ?? this.attachments,
      replyMessage: replyMessage ?? this.replyMessage,
      forwardedMessage: forwardedMessage ?? this.forwardedMessage,
      reactions: reactions ?? this.reactions,
      meta: meta ?? this.meta,
      sender: sender ?? this.sender,
    );
  }

  /// 序列化为 DB 存储 Map。
  Map<String, dynamic> toDbMap() => <String, dynamic>{
        'id': id,
        'room_id': roomId,
        'sender_id': senderId,
        'content': content,
        'status': status.name,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
        'nonce': nonce,
        'attachments_json': jsonEncode(attachments.map((a) => a.toJson()).toList()),
        'reply_message_id': replyMessage?.id,
        'forwarded_message_id': forwardedMessage?.id,
        'reactions_json': jsonEncode(reactions),
        'meta_json': meta != null ? jsonEncode(meta) : null,
        'sender_json': sender != null ? jsonEncode(sender!.toJson()) : null,
      };

  factory LocalChatMessage.fromDbMap(Map<String, dynamic> row) {
    List<SnChatAttachment> attachments = [];
    try {
      final raw = row['attachments_json'] as String?;
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        attachments = list
            .map((dynamic e) =>
                SnChatAttachment.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    Map<String, List<String>> reactions = {};
    try {
      final raw = row['reactions_json'] as String?;
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map;
        map.forEach((dynamic k, dynamic v) {
          if (v is List) {
            reactions[k.toString()] =
                v.map((dynamic e) => e.toString()).toList();
          }
        });
      }
    } catch (_) {}
    Map<String, dynamic>? meta;
    try {
      final raw = row['meta_json'] as String?;
      if (raw != null && raw.isNotEmpty) {
        meta = jsonDecode(raw) as Map<String, dynamic>?;
      }
    } catch (_) {}
    SnChatSender? sender;
    try {
      final raw = row['sender_json'] as String?;
      if (raw != null && raw.isNotEmpty) {
        sender =
            SnChatSender.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    MessageStatus status;
    switch (row['status'] as String?) {
      case 'pending':
        status = MessageStatus.pending;
      case 'failed':
        status = MessageStatus.failed;
      default:
        status = MessageStatus.sent;
    }
    return LocalChatMessage(
      id: (row['id'] as Object?)?.toString() ?? '',
      roomId: (row['room_id'] as Object?)?.toString() ?? '',
      senderId: (row['sender_id'] as Object?)?.toString() ?? '',
      content: (row['content'] as Object?)?.toString() ?? '',
      status: status,
      createdAt: row['created_at'] as String?,
      updatedAt: row['updated_at'] as String?,
      deletedAt: row['deleted_at'] as String?,
      nonce: row['nonce'] as String?,
      attachments: attachments,
      reactions: reactions,
      meta: meta,
      sender: sender,
    );
  }
}
