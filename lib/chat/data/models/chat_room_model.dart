import 'sn_chat_message.dart';

/// 聊天房间类型。
enum ChatRoomType {
  direct,
  group,
}

/// 聊天房间成员。
class ChatRoomMember {
  const ChatRoomMember({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.role,
    this.joinedAt,
    this.user,
  });

  final String id;
  final String roomId;
  final String userId;
  final String role;
  final String? joinedAt;
  final SnChatSender? user;

  factory ChatRoomMember.fromJson(Map<String, dynamic> json) => ChatRoomMember(
        id: (json['id'] as Object?)?.toString() ?? '',
        roomId: (json['room_id'] as Object?)?.toString() ?? '',
        userId: (json['user_id'] as Object?)?.toString() ?? '',
        role: (json['role'] as Object?)?.toString() ?? 'member',
        joinedAt: json['joined_at'] as String?,
        user: json['user'] != null
            ? SnChatSender.fromJson(json['user'] as Map<String, dynamic>)
            : null,
      );
}

/// 聊天房间。
class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    this.avatarUrl,
    this.memberCount = 0,
    this.lastMessageAt,
    this.createdAt,
    this.members = const [],
  });

  final String id;
  final String name;
  final ChatRoomType type;
  final String? description;
  final String? avatarUrl;
  final int memberCount;
  final String? lastMessageAt;
  final String? createdAt;
  final List<ChatRoomMember> members;

  bool get isDirect => type == ChatRoomType.direct;

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] as String?) ?? 'direct';
    final membersRaw = json['members'] as List?;
    return ChatRoom(
      id: (json['id'] as Object?)?.toString() ?? '',
      name: (json['name'] as Object?)?.toString() ?? '',
      type: typeStr == 'group' ? ChatRoomType.group : ChatRoomType.direct,
      description: json['description'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      memberCount: (json['member_count'] as int?) ?? 0,
      lastMessageAt: json['last_message_at'] as String?,
      createdAt: json['created_at'] as String?,
      members: membersRaw
              ?.map((dynamic e) =>
                  ChatRoomMember.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'type': type.name,
        'description': description,
        'avatar_url': avatarUrl,
        'member_count': memberCount,
        'last_message_at': lastMessageAt,
        'created_at': createdAt,
      };
}
