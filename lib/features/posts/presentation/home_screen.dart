import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../auth/data/models/user_model.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/models/post_model.dart';
import '../../social/providers/social_providers.dart';
import '../data/posts_repository.dart';
import '../providers/posts_providers.dart';

/// 首页：已登录显示时间线与发布 FAB，未登录显示登录/注册入口。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capslian'),
        actions: <Widget>[
          if (authState.valueOrNull != null) ...[
            IconButton(
              icon: const Icon(Icons.chat),
              onPressed: () => context.push(AppRoutes.direct),
            ),
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () => context.push(AppRoutes.profile),
            ),
          ],
        ],
      ),
      body: authState.when(
        data: (UserModel? user) {
          if (user == null) {
            return _buildGuestBody(context);
          }
          return _TimelineBody();
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object err, StackTrace? stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('加载失败'),
              TextButton(
                onPressed: () => context.push(AppRoutes.login),
                child: const Text('去登录'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: authState.valueOrNull != null
          ? FloatingActionButton(
              onPressed: () => context.push(AppRoutes.createPost),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildGuestBody(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Text('首页（时间线占位）'),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => context.push(AppRoutes.login),
            child: const Text('登录'),
          ),
          TextButton(
            onPressed: () => context.push(AppRoutes.register),
            child: const Text('注册'),
          ),
        ],
      ),
    );
  }
}

class _TimelineBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(postsListProvider(const PostsListKey()));
    return pageAsync.when(
      data: (PostsPageResult result) {
        if (result.posts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text('还没有帖子'),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.push(AppRoutes.createPost),
                  child: const Text('发一条'),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(postsListProvider(const PostsListKey()));
          },
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: result.posts.length,
            itemBuilder: (BuildContext context, int index) {
              return _PostTile(post: result.posts[index]);
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object err, StackTrace? stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('加载失败: ${err.toString()}'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(postsListProvider(const PostsListKey())),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostTile extends ConsumerWidget {
  const _PostTile({required this.post});
  final PostModel post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = post.user;
    final name = user?.displayName ?? user?.username ?? '未知用户';
    final authUser = ref.watch(authStateProvider).valueOrNull;
    final isOwnPost = authUser != null && authUser.id == post.userId;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 16,
                  child: user?.avatarUrl != null
                      ? ClipOval(child: Image.network(user!.avatarUrl!, width: 32, height: 32, fit: BoxFit.cover))
                      : Text(name.isNotEmpty ? name[0] : '?'),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(name, style: Theme.of(context).textTheme.titleSmall)),
                if (authUser != null && !isOwnPost)
                  TextButton(
                    onPressed: () async {
                      final repo = ref.read(socialRepositoryProvider);
                      await repo.follow(post.userId);
                      ref.invalidate(postsListProvider(const PostsListKey()));
                    },
                    child: const Text('关注'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(post.content),
            if (post.imageUrls != null && post.imageUrls!.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: post.imageUrls!.length,
                  separatorBuilder: (_, int i) => const SizedBox(width: 8),
                  itemBuilder: (_, int i) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(post.imageUrls![i], width: 120, height: 120, fit: BoxFit.cover),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                IconButton(
                  icon: Icon(post.liked ? Icons.favorite : Icons.favorite_border, color: post.liked ? Colors.red : null),
                  onPressed: authUser == null
                      ? null
                      : () async {
                          final repo = ref.read(socialRepositoryProvider);
                          if (post.liked) {
                            await repo.unlikePost(post.id);
                          } else {
                            await repo.likePost(post.id);
                          }
                          ref.invalidate(postsListProvider(const PostsListKey()));
                        },
                ),
                Text('${post.likeCount}'),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.comment_outlined),
                  onPressed: () => context.push('/posts/${post.id}/comments'),
                ),
                Text('${post.commentCount}'),
              ],
            ),
            if (post.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  post.createdAt!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
