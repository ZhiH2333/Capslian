import 'dart:convert' show jsonDecode;

/// 帖子模型，与 API 响应一致。
class PostModel {
  const PostModel({
    required this.id,
    required this.userId,
    required this.content,
    this.imageUrls,
    this.createdAt,
    this.updatedAt,
    this.likeCount = 0,
    this.liked = false,
    this.commentCount = 0,
    this.user,
  });

  final String id;
  final String userId;
  final String content;
  final List<String>? imageUrls;
  final String? createdAt;
  final String? updatedAt;
  final int likeCount;
  final bool liked;
  final int commentCount;
  final PostUser? user;

  factory PostModel.fromJson(Map<String, dynamic> json) {
    List<String>? urls;
    if (json['image_urls'] != null) {
      if (json['image_urls'] is List) {
        urls = (json['image_urls'] as List).map((e) => e.toString()).toList();
      } else if (json['image_urls'] is String) {
        try {
          final decoded = jsonDecode(json['image_urls'] as String) as List<dynamic>?;
          urls = decoded?.map((e) => e.toString()).toList();
        } catch (_) {
          urls = null;
        }
      }
    }
    PostUser? u;
    if (json['user'] is Map<String, dynamic>) {
      u = PostUser.fromJson(json['user'] as Map<String, dynamic>);
    }
    return PostModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      content: json['content'] as String,
      imageUrls: urls,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      liked: json['liked'] as bool? ?? false,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
      user: u,
    );
  }
}

/// 帖子中的用户摘要。
class PostUser {
  const PostUser({
    this.username,
    this.displayName,
    this.avatarUrl,
  });

  final String? username;
  final String? displayName;
  final String? avatarUrl;

  factory PostUser.fromJson(Map<String, dynamic> json) {
    return PostUser(
      username: json['username'] as String?,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
