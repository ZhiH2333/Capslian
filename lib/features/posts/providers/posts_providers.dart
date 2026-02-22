import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
import '../data/posts_repository.dart';

final postsRepositoryProvider = Provider<PostsRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return PostsRepository(dio: dio);
});

/// 时间线帖子列表（分页）；refresh 与 loadMore 由调用方触发。
final postsListProvider = FutureProvider.family<PostsPageResult, PostsListKey>((ref, key) async {
  final repo = ref.watch(postsRepositoryProvider);
  return repo.fetchPosts(limit: key.limit, cursor: key.cursor);
});

class PostsListKey {
  const PostsListKey({this.limit = 20, this.cursor});
  final int limit;
  final String? cursor;
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PostsListKey && limit == other.limit && cursor == other.cursor;
  @override
  int get hashCode => Object.hash(limit, cursor);
}
