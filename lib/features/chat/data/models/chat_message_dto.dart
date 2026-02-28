/// 后端消息 DTO：与 API/WebSocket 对齐。
/// 字段：id, content, sender_id, created_at, local_id（及可选 attachments 等）。
class ChatMessageDto {
  const ChatMessageDto({
    required this.id,
    required this.content,
    required this.senderId,
    this.createdAt,
    this.localId,
    this.attachments = const [],
    this.roomId,
  });

  final String id;
  final String content;
  final String senderId;
  final String? createdAt;
  final String? localId;
  final List<ChatAttachmentDto> attachments;
  final String? roomId;

  factory ChatMessageDto.fromJson(Map<String, dynamic> json) {
    final attachmentsRaw = json['attachments'] as List?;
    final attachments =
        attachmentsRaw
            ?.map(
              (dynamic e) =>
                  ChatAttachmentDto.fromJson(e as Map<String, dynamic>),
            )
            .toList() ??
        [];
    return ChatMessageDto(
      id: (json['id'] as Object?)?.toString() ?? '',
      content: (json['content'] as Object?)?.toString() ?? '',
      senderId: (json['sender_id'] as Object?)?.toString() ?? '',
      createdAt: json['created_at'] as String?,
      localId:
          (json['local_id'] as Object?)?.toString() ??
          (json['nonce'] as Object?)?.toString(),
      roomId:
          (json['room_id'] as Object?)?.toString() ??
          (json['chat_room_id'] as Object?)?.toString(),
      attachments: attachments,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'content': content,
    'sender_id': senderId,
    'created_at': createdAt,
    'local_id': localId,
    'room_id': roomId,
    'attachments': attachments.map((a) => a.toJson()).toList(),
  };
}

class ChatAttachmentDto {
  const ChatAttachmentDto({
    required this.id,
    required this.name,
    required this.url,
    this.mimeType,
  });

  final String id;
  final String name;
  final String url;
  final String? mimeType;

  factory ChatAttachmentDto.fromJson(Map<String, dynamic> json) =>
      ChatAttachmentDto(
        id: (json['id'] as Object?)?.toString() ?? '',
        name: (json['name'] as Object?)?.toString() ?? '',
        url: (json['url'] as Object?)?.toString() ?? '',
        mimeType: json['mime_type'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'url': url,
    'mime_type': mimeType,
  };

  bool get isImage {
    final mime = mimeType ?? '';
    return mime.startsWith('image/');
  }
}
