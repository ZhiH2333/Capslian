import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import '../../auth/data/models/user_model.dart';

/// 当前用户资料更新。
class ProfileRepository {
  ProfileRepository({required Dio dio}) : _dio = dio;
  final Dio _dio;

  Future<UserModel> updateMe({
    String? displayName,
    String? bio,
    String? avatarUrl,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['display_name'] = displayName;
    if (bio != null) body['bio'] = bio;
    if (avatarUrl != null) body['avatar_url'] = avatarUrl;
    if (body.isEmpty) throw Exception('无有效字段');
    final response = await _dio.patch<Map<String, dynamic>>(ApiConstants.usersMe, data: body);
    final data = response.data;
    if (data == null || data['user'] == null) throw Exception('更新响应异常');
    return UserModel.fromJson(data['user'] as Map<String, dynamic>);
  }
}
