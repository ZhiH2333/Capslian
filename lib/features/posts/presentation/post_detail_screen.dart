import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../../social/providers/social_providers.dart';
import '../data/models/post_model.dart';
import '../providers/posts_providers.dart';
import 'widgets/post_card.dart';

/// 帖子详情页：展示完整帖子内容与评论列表。
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId, this.initialPost});

  final String postId;

  /// 可选的初始帖子数据，避免从列表进入时出现加载闪烁。
  final PostModel? initialPost;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _comments = [];
  bool _loadingComments = true;
  bool _sending = false;
  String? _commentError;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    setState(() {
      _loadingComments = true;
      _commentError = null;
    });
    try {
      final repo = ref.read(socialRepositoryProvider);
      final list = await repo.getComments(widget.postId);
      if (mounted) {
        setState(() {
          _comments
            ..clear()
            ..addAll(list);
          _loadingComments = false;
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _commentError = err.toString();
          _loadingComments = false;
        });
      }
    }
  }

  Future<void> _sendComment() async {
    final String content = _commentController.text.trim();
    if (content.isEmpty) return;
    setState(() {
      _sending = true;
      _commentError = null;
    });
    _commentController.clear();
    try {
      final repo = ref.read(socialRepositoryProvider);
      final Map<String, dynamic> comment = await repo.addComment(widget.postId, content);
      if (mounted) {
        setState(() {
          _comments.insert(0, comment);
          _sending = false;
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _commentError = err.toString();
          _sending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final postAsync = ref.watch(postDetailProvider(widget.postId));
    final double bottomPadding = MediaQuery.paddingOf(context).bottom;
    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: const Text('帖子详情'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: postAsync.when(
              data: (PostModel? post) {
                final PostModel? displayPost = post ?? widget.initialPost;
                if (displayPost == null) {
                  return const Center(child: Text('帖子不存在'));
                }
                return _DetailContent(
                  post: displayPost,
                  comments: _comments,
                  loadingComments: _loadingComments,
                  commentError: _commentError,
                  scrollController: _scrollController,
                  onRefresh: _loadComments,
                );
              },
              loading: () {
                if (widget.initialPost != null) {
                  return _DetailContent(
                    post: widget.initialPost!,
                    comments: _comments,
                    loadingComments: _loadingComments,
                    commentError: _commentError,
                    scrollController: _scrollController,
                    onRefresh: _loadComments,
                  );
                }
                return const Center(child: CircularProgressIndicator());
              },
              error: (_, __) {
                if (widget.initialPost != null) {
                  return _DetailContent(
                    post: widget.initialPost!,
                    comments: _comments,
                    loadingComments: _loadingComments,
                    commentError: _commentError,
                    scrollController: _scrollController,
                    onRefresh: _loadComments,
                  );
                }
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Text('加载失败'),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.invalidate(postDetailProvider(widget.postId)),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          _CommentInputBar(
            controller: _commentController,
            isSending: _sending,
            onSend: _sendComment,
            bottomPadding: bottomPadding,
          ),
        ],
      ),
    );
  }
}

/// 详情内容主体：帖子卡片 + 评论列表。
class _DetailContent extends StatelessWidget {
  const _DetailContent({
    required this.post,
    required this.comments,
    required this.loadingComments,
    this.commentError,
    required this.scrollController,
    required this.onRefresh,
  });

  final PostModel post;
  final List<Map<String, dynamic>> comments;
  final bool loadingComments;
  final String? commentError;
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: LayoutConstants.kContentMaxWidthWide),
        child: RefreshIndicator(
          onRefresh: onRefresh,
          child: CustomScrollView(
            controller: scrollController,
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: PostCard(post: post, isDetailView: true),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '${comments.isEmpty && !loadingComments ? '暂无' : ''}评论',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: Divider(height: 1, thickness: 0.5)),
              if (loadingComments)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (commentError != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text(commentError!)),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, int i) => _CommentItem(comment: comments[i]),
                    childCount: comments.length,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 评论列表项。
class _CommentItem extends StatelessWidget {
  const _CommentItem({required this.comment});

  final Map<String, dynamic> comment;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? user =
        comment['user'] is Map ? comment['user'] as Map<String, dynamic> : null;
    final String name = user?['display_name'] as String? ??
        user?['username'] as String? ??
        comment['display_name']?.toString() ??
        comment['username']?.toString() ??
        '未知用户';
    final String? avatarUrl = user?['avatar_url'] as String?;
    final String content = comment['content']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CommentAvatar(name: name, avatarUrl: avatarUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  content,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 评论头像（圆形，支持网络图或首字母占位）。
class _CommentAvatar extends StatelessWidget {
  const _CommentAvatar({required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return CircleAvatar(
      radius: 16,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: avatarUrl != null
          ? ClipOval(
              child: Image.network(
                avatarUrl!,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildInitial(theme),
              ),
            )
          : _buildInitial(theme),
    );
  }

  Widget _buildInitial(ThemeData theme) {
    return Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onPrimaryContainer,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

/// 底部评论输入栏。
class _CommentInputBar extends StatelessWidget {
  const _CommentInputBar({
    required this.controller,
    required this.isSending,
    required this.onSend,
    required this.bottomPadding,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
        color: Theme.of(context).colorScheme.surface,
      ),
      padding: EdgeInsets.fromLTRB(16, 8, 8, 8 + bottomPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '写评论...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: isSending ? null : onSend,
            icon: isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
