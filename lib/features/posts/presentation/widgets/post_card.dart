import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/data/models/user_model.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../social/providers/social_providers.dart';
import '../../data/models/post_model.dart';
import '../../providers/posts_providers.dart';

/// 将数字格式化为 K/M 简写（如 1800 → 1.8K）。
String _formatCount(int count) {
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
  return '$count';
}

/// 将 ISO 8601 时间字符串转为相对时间（如 "20h"、"2d"）。
String _formatRelativeTime(String? isoTime) {
  if (isoTime == null) return '';
  try {
    final created = DateTime.parse(isoTime).toLocal();
    final diff = DateTime.now().difference(created);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 365) return '${diff.inDays}d';
    return '${(diff.inDays / 365).floor()}y';
  } catch (_) {
    return isoTime;
  }
}

/// X.com 风格帖子卡片。
class PostCard extends ConsumerWidget {
  const PostCard({super.key, required this.post});

  final PostModel post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(authStateProvider).valueOrNull;
    final isOwnPost = authUser != null && authUser.id == post.userId;
    final user = post.user;
    final name = user?.displayName ?? user?.username ?? '未知用户';
    final handle = user?.username ?? '';
    final timeAgo = _formatRelativeTime(post.createdAt);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        InkWell(
          onTap: () => context.push('/posts/${post.id}/comments'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _PostAvatar(user: user, name: name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _PostHeader(
                        name: name,
                        handle: handle,
                        timeAgo: timeAgo,
                        post: post,
                        authUser: authUser,
                        isOwnPost: isOwnPost,
                        ref: ref,
                      ),
                      const SizedBox(height: 4),
                      _PostContent(content: post.content),
                      if (post.imageUrls != null && post.imageUrls!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        _PostImages(imageUrls: post.imageUrls!),
                      ],
                      const SizedBox(height: 12),
                      _PostActionBar(post: post, authUser: authUser, ref: ref),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, thickness: 0.5),
      ],
    );
  }
}

/// 用户头像。
class _PostAvatar extends StatelessWidget {
  const _PostAvatar({required this.user, required this.name});

  final dynamic user;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 20,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: user?.avatarUrl != null
          ? ClipOval(
              child: Image.network(
                user!.avatarUrl as String,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildInitial(theme, name),
              ),
            )
          : _buildInitial(theme, name),
    );
  }

  Widget _buildInitial(ThemeData theme, String name) {
    return Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.onPrimaryContainer,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

/// 帖子头部：用户名、handle、时间、更多菜单。
class _PostHeader extends StatelessWidget {
  const _PostHeader({
    required this.name,
    required this.handle,
    required this.timeAgo,
    required this.post,
    required this.authUser,
    required this.isOwnPost,
    required this.ref,
  });

  final String name;
  final String handle;
  final String timeAgo;
  final PostModel post;
  final UserModel? authUser;
  final bool isOwnPost;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryColor = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (handle.isNotEmpty)
                  TextSpan(
                    text: '  @$handle',
                    style: theme.textTheme.bodySmall?.copyWith(color: secondaryColor),
                  ),
                if (timeAgo.isNotEmpty)
                  TextSpan(
                    text: ' · $timeAgo',
                    style: theme.textTheme.bodySmall?.copyWith(color: secondaryColor),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _MoreMenu(post: post, authUser: authUser, isOwnPost: isOwnPost, ref: ref),
      ],
    );
  }
}

/// 更多操作菜单（删除等）。
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.post,
    required this.authUser,
    required this.isOwnPost,
    required this.ref,
  });

  final PostModel post;
  final UserModel? authUser;
  final bool isOwnPost;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: Icon(Icons.more_horiz, color: Theme.of(context).colorScheme.onSurfaceVariant),
        onSelected: (String value) => _handleMenuAction(context, value),
        itemBuilder: (_) => _buildMenuItems(),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(
        value: 'copy',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.copy_outlined, size: 18),
            SizedBox(width: 12),
            Text('复制链接'),
          ],
        ),
      ),
    ];
    if (isOwnPost) {
      items.add(
        const PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.delete_outline, size: 18, color: Colors.red),
              SizedBox(width: 12),
              Text('删除', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      );
    }
    return items;
  }

  Future<void> _handleMenuAction(BuildContext context, String value) async {
    if (value != 'delete') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除帖子'),
        content: const Text('确定要删除这条帖子吗？删除后无法恢复。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
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
  }
}

/// 帖子正文内容。
class _PostContent extends StatelessWidget {
  const _PostContent({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      content,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface,
        height: 1.4,
      ),
    );
  }
}

/// 图片区域：1 张全宽，2 张并排，3-4 张网格。
class _PostImages extends StatelessWidget {
  const _PostImages({required this.imageUrls});

  final List<String> imageUrls;

  @override
  Widget build(BuildContext context) {
    if (imageUrls.length == 1) return _buildSingleImage(imageUrls[0]);
    if (imageUrls.length == 2) return _buildTwoImages();
    return _buildGrid();
  }

  Widget _buildSingleImage(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _ImagePlaceholder(),
        ),
      ),
    );
  }

  Widget _buildTwoImages() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Row(
          children: <Widget>[
            Expanded(child: _buildNetworkImage(imageUrls[0], rightGap: true)),
            Expanded(child: _buildNetworkImage(imageUrls[1])),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    final count = imageUrls.length.clamp(0, 4);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: count,
          itemBuilder: (_, int i) => _buildNetworkImage(imageUrls[i]),
        ),
      ),
    );
  }

  Widget _buildNetworkImage(String url, {bool rightGap = false}) {
    return Padding(
      padding: EdgeInsets.only(right: rightGap ? 2 : 0),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _ImagePlaceholder(),
      ),
    );
  }
}

/// 图片加载失败占位。
class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Icon(Icons.broken_image_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

/// 底部操作栏：评论、转帖、喜欢、浏览量 / 收藏、转发。
class _PostActionBar extends ConsumerStatefulWidget {
  const _PostActionBar({required this.post, required this.authUser, required this.ref});

  final PostModel post;
  final UserModel? authUser;
  final WidgetRef ref;

  @override
  ConsumerState<_PostActionBar> createState() => _PostActionBarState();
}

class _PostActionBarState extends ConsumerState<_PostActionBar> {
  late bool _liked;
  late int _likeCount;
  late bool _isReposted;
  late int _repostCount;
  late bool _isBookmarked;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.liked;
    _likeCount = widget.post.likeCount;
    _isReposted = widget.post.isReposted;
    _repostCount = widget.post.repostCount;
    _isBookmarked = widget.post.isBookmarked;
  }

  Future<void> _toggleLike() async {
    if (widget.authUser == null) return;
    final repo = ref.read(socialRepositoryProvider);
    setState(() {
      if (_liked) {
        _liked = false;
        _likeCount = (_likeCount - 1).clamp(0, 999999999);
      } else {
        _liked = true;
        _likeCount += 1;
      }
    });
    try {
      if (!_liked) {
        await repo.unlikePost(widget.post.id);
      } else {
        await repo.likePost(widget.post.id);
      }
    } catch (_) {
      setState(() {
        _liked = !_liked;
        _likeCount += _liked ? 1 : -1;
      });
    }
  }

  void _toggleRepost() {
    if (widget.authUser == null) return;
    setState(() {
      if (_isReposted) {
        _isReposted = false;
        _repostCount = (_repostCount - 1).clamp(0, 999999999);
      } else {
        _isReposted = true;
        _repostCount += 1;
      }
    });
  }

  void _toggleBookmark() {
    if (widget.authUser == null) return;
    setState(() => _isBookmarked = !_isBookmarked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultColor = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: <Widget>[
        _ActionButton(
          icon: Icons.chat_bubble_outline,
          count: widget.post.commentCount,
          color: defaultColor,
          activeColor: const Color(0xFF1D9BF0),
          onTap: () => context.push('/posts/${widget.post.id}/comments'),
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: Icons.repeat,
          count: _repostCount,
          color: _isReposted ? const Color(0xFF00BA7C) : defaultColor,
          activeColor: const Color(0xFF00BA7C),
          isActive: _isReposted,
          onTap: _toggleRepost,
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: _liked ? Icons.favorite : Icons.favorite_border,
          count: _likeCount,
          color: _liked ? const Color(0xFFF91880) : defaultColor,
          activeColor: const Color(0xFFF91880),
          isActive: _liked,
          onTap: _toggleLike,
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: Icons.bar_chart,
          count: widget.post.viewCount,
          color: defaultColor,
          activeColor: const Color(0xFF1D9BF0),
          onTap: null,
        ),
        const Spacer(),
        _IconActionButton(
          icon: _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
          color: _isBookmarked ? const Color(0xFF1D9BF0) : defaultColor,
          onTap: _toggleBookmark,
        ),
        const SizedBox(width: 4),
        _IconActionButton(
          icon: Icons.ios_share_outlined,
          color: defaultColor,
          onTap: () {},
        ),
      ],
    );
  }
}

/// 带数字的操作按钮（评论、转帖、喜欢、浏览量）。
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.count,
    required this.color,
    required this.activeColor,
    this.isActive = false,
    required this.onTap,
  });

  final IconData icon;
  final int count;
  final Color color;
  final Color activeColor;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final displayCount = count > 0 ? _formatCount(count) : '';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 18, color: color),
            if (displayCount.isNotEmpty) ...<Widget>[
              const SizedBox(width: 4),
              Text(
                displayCount,
                style: TextStyle(fontSize: 13, color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 仅图标操作按钮（收藏、转发）。
class _IconActionButton extends StatelessWidget {
  const _IconActionButton({required this.icon, required this.color, required this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
