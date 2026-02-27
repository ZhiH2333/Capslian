/// 服务端返回的聊天消息发送者信息。
class SnChatSender {
  const SnChatSender({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;

  String get name => displayName?.isNotEmpty == true ? displayName! : username;

  factory SnChatSender.fromJson(Map<String, dynamic> json) => SnChatSender(
        id: (json['id'] as Object?)?.toString() ?? '',
        username: (json['username'] as Object?)?.toString() ?? '',
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
      };
}

/// 服务端返回的消息附件。
class SnChatAttachment {
  const SnChatAttachment({
    required this.id,
    required this.name,
    required this.url,
    this.mimeType,
    this.size,
  });

  final String id;
  final String name;
  final String url;
  final String? mimeType;
  final int? size;

  bool get isImage {
    final mime = mimeType ?? '';
    return mime.startsWith('image/');
  }

  factory SnChatAttachment.fromJson(Map<String, dynamic> json) =>
      SnChatAttachment(
        id: (json['id'] as Object?)?.toString() ?? '',
        name: (json['name'] as Object?)?.toString() ?? '',
        url: (json['url'] as Object?)?.toString() ?? '',
        mimeType: json['mime_type'] as String?,
        size: json['size'] as int?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'url': url,
        'mime_type': mimeType,
        'size': size,
      };
}

/// 服务端返回的完整聊天消息。
class SnChatMessage {
  const SnChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.content,
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
  final String? createdAt;
  final String? updatedAt;
  final String? deletedAt;
  final String? nonce;
  final List<SnChatAttachment> attachments;
  final SnChatMessage? replyMessage;
  final SnChatMessage? forwardedMessage;

  /// 反应表：emoji → 用户 ID 列表。
  final Map<String, List<String>> reactions;
  final Map<String, dynamic>? meta;
  final SnChatSender? sender;

  bool get isDeleted => deletedAt != null;

  factory SnChatMessage.fromJson(Map<String, dynamic> json) {
    final attachmentsRaw = json['attachments'] as List?;
    final attachments = attachmentsRaw
            ?.map((dynamic e) =>
                SnChatAttachment.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final reactionsRaw = json['reactions'] as Map?;
    final reactions = <String, List<String>>{};
    reactionsRaw?.forEach((dynamic k, dynamic v) {
      if (v is List) {
        reactions[k.toString()] =
            v.map((dynamic e) => e.toString()).toList();
      }
    });
    return SnChatMessage(
      id: (json['id'] as Object?)?.toString() ?? '',
      roomId: (json['room_id'] as Object?)?.toString() ??
          (json['chat_room_id'] as Object?)?.toString() ??
          '',
      senderId: (json['sender_id'] as Object?)?.toString() ?? '',
      content: (json['content'] as Object?)?.toString() ?? '',
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      deletedAt: json['deleted_at'] as String?,
      nonce: json['nonce'] as String?,
      attachments: attachments,
      replyMessage: json['reply_message'] != null
          ? SnChatMessage.fromJson(
              json['reply_message'] as Map<String, dynamic>)
          : null,
      forwardedMessage: json['forwarded_message'] != null
          ? SnChatMessage.fromJson(
              json['forwarded_message'] as Map<String, dynamic>)
          : null,
      reactions: reactions,
      meta: json['meta'] as Map<String, dynamic>?,
      sender: json['sender'] != null
          ? SnChatSender.fromJson(json['sender'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'room_id': roomId,
        'sender_id': senderId,
        'content': content,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
        'nonce': nonce,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'reply_message': replyMessage?.toJson(),
        'forwarded_message': forwardedMessage?.toJson(),
        'reactions': reactions,
        'meta': meta,
        'sender': sender?.toJson(),
      };
}
