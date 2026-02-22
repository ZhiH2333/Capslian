import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import 'models/post_model.dart';

/// 帖子列表分页结果。
class PostsPageResult {
  const PostsPageResult({required this.posts, this.nextCursor});
  final List<PostModel> posts;
  final String? nextCursor;
}

/// 帖子接口：列表、发布、单条、上传图片。
class PostsRepository {
  PostsRepository({required Dio dio}) : _dio = dio;
  final Dio _dio;

  Future<PostsPageResult> fetchPosts({int limit = 20, String? cursor}) async {
    final query = <String, dynamic>{'limit': limit};
    if (cursor != null && cursor.isNotEmpty) query['cursor'] = cursor;
    final uri = Uri.parse(ApiConstants.posts).replace(queryParameters: query);
    final response = await _dio.get<Map<String, dynamic>>(uri.toString());
    final data = response.data;
    if (data == null || data['posts'] is! List) return const PostsPageResult(posts: []);
    final list = (data['posts'] as List).map((e) => PostModel.fromJson(e as Map<String, dynamic>)).toList();
    final nextCursor = data['nextCursor'] as String?;
    return PostsPageResult(posts: list, nextCursor: nextCursor);
  }

  Future<PostModel> createPost({required String content, List<String>? imageUrls}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiConstants.posts,
      data: <String, dynamic>{
        'content': content,
        if (imageUrls != null && imageUrls.isNotEmpty) 'image_urls': imageUrls,
      },
    );
    final data = response.data;
    if (data == null || data['post'] == null) throw Exception('发布响应异常');
    return PostModel.fromJson(data['post'] as Map<String, dynamic>);
  }

  Future<PostModel?> getPost(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('${ApiConstants.posts}/$id');
      final data = response.data;
      if (data == null || data['post'] == null) return null;
      return PostModel.fromJson(data['post'] as Map<String, dynamic>);
    } on DioException catch (_) {
      return null;
    }
  }

  /// 上传单张图片，返回可访问的 URL。
  Future<String> uploadImage(String path, {required String mimeType}) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: path.split('/').last),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      ApiConstants.upload,
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    final data = response.data;
    if (data == null || data['url'] is! String) throw Exception('上传响应异常');
    final url = data['url'] as String;
    if (url.startsWith('http')) return url;
    return '${ApiConstants.baseUrl}$url';
  }
}
