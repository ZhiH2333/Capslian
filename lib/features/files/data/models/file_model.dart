/// 文件模型，与 API 响应一致。
class FileModel {
  const FileModel({
    required this.id,
    required this.userId,
    required this.key,
    required this.name,
    this.size = 0,
    this.mimeType,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String key;
  final String name;
  final int size;
  final String? mimeType;
  final String? createdAt;

  factory FileModel.fromJson(Map<String, dynamic> json) {
    return FileModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      key: json['key'] as String,
      name: json['name'] as String,
      size: (json['size'] as num?)?.toInt() ?? 0,
      mimeType: json['mime_type'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}
