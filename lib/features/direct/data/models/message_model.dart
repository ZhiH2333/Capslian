/// 消息类型：文本、图片、文件。
enum MessageType {
  text,
  image,
  file,
}

/// 消息发送/已读状态（客户端展示用）。
enum MessageStatus {
  sending,
  sent,
  failed,
  read,
}

/// 单条私信模型，支持类型、状态与已读。
class MessageModel {
  const MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.createdAt,
    this.type = MessageType.text,
    this.status = MessageStatus.sent,
    this.read = false,
    this.readAt,
    this.attachmentUrl,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final String? createdAt;
  final MessageType type;
  final MessageStatus status;
  final bool read;
  final String? readAt;
  final String? attachmentUrl;

  static MessageType _parseType(String? value) {
    if (value == null) return MessageType.text;
    switch (value) {
      case 'image':
        return MessageType.image;
      case 'file':
        return MessageType.file;
      default:
        return MessageType.text;
    }
  }

  static MessageStatus _parseStatus(String? value) {
    if (value == null) return MessageStatus.sent;
    switch (value) {
      case 'sending':
        return MessageStatus.sending;
      case 'failed':
        return MessageStatus.failed;
      case 'read':
        return MessageStatus.read;
      default:
        return MessageStatus.sent;
    }
  }

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: (json['id'] as Object?).toString(),
      senderId: (json['sender_id'] as Object?).toString(),
      receiverId: (json['receiver_id'] as Object?).toString(),
      content: (json['content'] as Object?).toString(),
      createdAt: json['created_at'] as String?,
      type: _parseType(json['type'] as String?),
      status: _parseStatus(json['status'] as String?),
      read: json['read'] == true || json['read'] == 1,
      readAt: json['read_at'] as String?,
      attachmentUrl: json['attachment_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'sender_id': senderId,
        'receiver_id': receiverId,
        'content': content,
        'created_at': createdAt,
        'type': type.name,
        'status': status.name,
        'read': read,
        'read_at': readAt,
        'attachment_url': attachmentUrl,
      };

  MessageModel copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? content,
    String? createdAt,
    MessageType? type,
    MessageStatus? status,
    bool? read,
    String? readAt,
    String? attachmentUrl,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      type: type ?? this.type,
      status: status ?? this.status,
      read: read ?? this.read,
      readAt: readAt ?? this.readAt,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
    );
  }
}
