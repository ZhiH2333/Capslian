import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';

/// 点赞、评论、关注、私信接口。
class SocialRepository {
  SocialRepository({required Dio dio}) : _dio = dio;
  final Dio _dio;

  Future<void> likePost(String postId) async {
    await _dio.post<Map<String, dynamic>>('${ApiConstants.posts}/$postId/like');
  }

  Future<void> unlikePost(String postId) async {
    await _dio.delete<Map<String, dynamic>>('${ApiConstants.posts}/$postId/like');
  }

  Future<void> follow(String followingId) async {
    await _dio.post<Map<String, dynamic>>(ApiConstants.follows, data: <String, dynamic>{'following_id': followingId});
  }

  Future<void> unfollow(String followingId) async {
    await _dio.delete<Map<String, dynamic>>('${ApiConstants.follows}/$followingId');
  }

  Future<List<Map<String, dynamic>>> getComments(String postId) async {
    final response = await _dio.get<Map<String, dynamic>>('${ApiConstants.posts}/$postId/comments');
    final data = response.data;
    if (data == null || data['comments'] is! List) return [];
    return List<Map<String, dynamic>>.from(data['comments'] as List);
  }

  Future<Map<String, dynamic>> addComment(String postId, String content) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '${ApiConstants.posts}/$postId/comments',
      data: <String, dynamic>{'content': content},
    );
    final data = response.data;
    if (data == null || data['comment'] == null) throw Exception('评论失败');
    return data['comment'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    final response = await _dio.get<Map<String, dynamic>>(ApiConstants.messages);
    final data = response.data;
    if (data == null || data['conversations'] is! List) return [];
    return List<Map<String, dynamic>>.from(data['conversations'] as List);
  }

  Future<List<Map<String, dynamic>>> getMessages(String withUserId, {String? cursor}) async {
    final uri = Uri.parse(ApiConstants.messages).replace(
      queryParameters: <String, String>{'with_user': withUserId, ...? (cursor != null ? <String, String>{'cursor': cursor} : null)},
    );
    final response = await _dio.get<Map<String, dynamic>>(uri.toString());
    final data = response.data;
    if (data == null || data['messages'] is! List) return [];
    return List<Map<String, dynamic>>.from(data['messages'] as List);
  }

  Future<Map<String, dynamic>> sendMessage(String receiverId, String content) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiConstants.messages,
      data: <String, dynamic>{'receiver_id': receiverId, 'content': content},
    );
    final data = response.data;
    if (data == null || data['message'] == null) throw Exception('发送失败');
    return data['message'] as Map<String, dynamic>;
  }
}
