/// 通知模型，与 API 响应一致。
class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    this.title,
    this.body,
    this.data,
    this.read = false,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String type;
  final String? title;
  final String? body;
  final Map<String, dynamic>? data;
  final bool read;
  final String? createdAt;

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    bool readVal = false;
    if (json['read'] != null) {
      if (json['read'] is bool) {
        readVal = json['read'] as bool;
      } else if (json['read'] is int) {
        readVal = (json['read'] as int) != 0;
      }
    }
    Map<String, dynamic>? dataMap;
    if (json['data'] != null && json['data'] is Map) {
      dataMap = Map<String, dynamic>.from(json['data'] as Map<dynamic, dynamic>);
    }
    return NotificationModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      title: json['title'] as String?,
      body: json['body'] as String?,
      data: dataMap,
      read: readVal,
      createdAt: json['created_at'] as String?,
    );
  }
}
