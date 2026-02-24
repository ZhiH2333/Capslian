import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/responsive.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../auth/data/models/user_model.dart';
import '../../auth/providers/auth_providers.dart';
import '../../social/providers/social_providers.dart';
import '../data/models/post_model.dart';
import '../data/posts_repository.dart';
import '../providers/posts_providers.dart';

/// 首页：已登录显示时间线与发布 FAB，未登录显示登录/注册入口。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.inShell = false});

  /// 是否嵌入底部导航壳；为 true 时不显示顶部聊天/个人入口。
  final bool inShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final wide = isWideScreen(context);
    return AppScaffold(
      isNoBackground: wide,
      isWideScreen: wide,
      appBar: inShell
          ? null
          : AppBar(
              title: const Text('Molian'),
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
        error: (Object err, StackTrace? stack) => EmptyState(
          title: '加载失败',
          description: err.toString(),
          action: TextButton(
            onPressed: () => context.push(AppRoutes.login),
            child: const Text('去登录'),
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
          return EmptyState(
            title: '还没有帖子',
            description: '发一条动态吧',
            icon: Icons.edit_note,
            action: FilledButton.icon(
              onPressed: () => context.push(AppRoutes.createPost),
              icon: const Icon(Icons.add),
              label: const Text('发一条'),
            ),
          );
        }
        final bottomPadding = MediaQuery.paddingOf(context).bottom + 64;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(postsListProvider(const PostsListKey()));
          },
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: LayoutConstants.kContentMaxWidthWide),
              child: ListView.builder(
                padding: EdgeInsets.only(
                  top: LayoutConstants.kSpacingSmall,
                  bottom: bottomPadding,
                  left: LayoutConstants.kSpacingSmall,
                  right: LayoutConstants.kSpacingSmall,
                ),
                itemCount: result.posts.length,
                itemBuilder: (BuildContext context, int index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: LayoutConstants.kSpacingSmall),
                    child: _PostTile(post: result.posts[index]),
                  );
                },
              ),
            ),
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

/// 从帖子 content 解析出标题、描述、正文（按换行拆分）。
({String title, String description, String content}) _parsePostContent(String content) {
  final lines = content.split('\n');
  final title = lines.isNotEmpty ? lines[0].trim() : '';
  final description = lines.length > 1 ? lines[1].trim() : '';
  final body = lines.length > 2 ? lines.sublist(2).join('\n').trim() : '';
  return (title: title, description: description, content: body.isEmpty && title.isNotEmpty ? '' : body);
}

class _PostTile extends ConsumerWidget {
  const _PostTile({required this.post});
  final PostModel post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = post.user;
    final name = user?.displayName ?? user?.username ?? '未知用户';
    final handle = user?.username != null ? '@${user!.username}' : '';
    final authUser = ref.watch(authStateProvider).valueOrNull;
    final isOwnPost = authUser != null && authUser.id == post.userId;
    final parsed = _parsePostContent(post.content);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: LayoutConstants.kRadiusMediumBR),
      color: theme.cardTheme.color ?? theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: user?.avatarUrl != null
                      ? ClipOval(
                          child: Image.network(
                            user!.avatarUrl!,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Text(
                          name.isNotEmpty ? name[0] : '?',
                          style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        children: <Widget>[
                          Text(
                            name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.brightness == Brightness.dark
                                  ? const Color(0xFF90CAF9)
                                  : theme.colorScheme.primary,
                            ),
                          ),
                          Icon(Icons.star, size: 14, color: theme.colorScheme.primary),
                          if (handle.isNotEmpty)
                            Text(
                              handle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      if (post.createdAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            post.createdAt!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _ReactButton(post: post, authUser: authUser),
                if (isOwnPost)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (String value) async {
                      if (value != 'delete') return;
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (BuildContext ctx) => AlertDialog(
                          title: const Text('删除帖子'),
                          content: const Text('确定要删除这条帖子吗？删除后无法恢复。'),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true || !context.mounted) return;
                      try {
                        final repo = ref.read(postsRepositoryProvider);
                        await repo.deletePost(post.id);
                        if (context.mounted) ref.invalidate(postsListProvider(const PostsListKey()));
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
                        }
                      }
                    },
                    itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.delete_outline, size: 20, color: Colors.red),
                            const SizedBox(width: 8),
                            Text('删除', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (parsed.title.isNotEmpty || parsed.description.isNotEmpty || parsed.content.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (parsed.title.isNotEmpty)
                      Text(
                        parsed.title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    if (parsed.description.isNotEmpty) ...[
                      if (parsed.title.isNotEmpty) const SizedBox(height: 4),
                      Text(
                        parsed.description,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    if (parsed.content.isNotEmpty) ...[
                      if (parsed.title.isNotEmpty || parsed.description.isNotEmpty) const SizedBox(height: 4),
                      Text(
                        parsed.content,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ],
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
                      child: Image.network(
                        post.imageUrls![i],
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                IconButton(
                  icon: Icon(
                    post.liked ? Icons.favorite : Icons.favorite_border,
                    color: post.liked ? Colors.red : null,
                  ),
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
            const SizedBox(height: 8),
            _ReplySection(
              postId: post.id,
              commentCount: post.commentCount,
              authorAvatarUrl: user?.avatarUrl,
              authorName: name,
            ),
            if (authUser != null && !isOwnPost)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      final repo = ref.read(socialRepositoryProvider);
                      await repo.follow(post.userId);
                      ref.invalidate(postsListProvider(const PostsListKey()));
                    },
                    child: const Text('关注'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 右上角反应入口：图标 + 绿色角标数量。
class _ReactButton extends ConsumerStatefulWidget {
  const _ReactButton({required this.post, required this.authUser});
  final PostModel post;
  final UserModel? authUser;

  @override
  ConsumerState<_ReactButton> createState() => _ReactButtonState();
}

class _ReactButtonState extends ConsumerState<_ReactButton> {
  int _reactCount = 0;

  @override
  void initState() {
    super.initState();
    _reactCount = widget.post.likeCount;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.authUser == null
          ? null
          : () {
              setState(() => _reactCount = _reactCount == 0 ? 1 : 0);
            },
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: <Widget>[
            Icon(
              Icons.emoji_emotions_outlined,
              size: 28,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'x$_reactCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 回复区域：圆角框内显示回复数与一条预览。
class _ReplySection extends StatelessWidget {
  const _ReplySection({
    required this.postId,
    required this.commentCount,
    this.authorAvatarUrl,
    required this.authorName,
  });
  final String postId;
  final int commentCount;
  final String? authorAvatarUrl;
  final String authorName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => context.push('/posts/$postId/comments'),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$commentCount reply',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (commentCount > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: authorAvatarUrl != null
                          ? ClipOval(
                              child: Image.network(
                                authorAvatarUrl!,
                                width: 24,
                                height: 24,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Text(
                              authorName.isNotEmpty ? authorName[0] : '?',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Reply1',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
