import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../../auth/providers/auth_providers.dart';
import '../../social/providers/social_providers.dart';
import '../data/models/post_model.dart';
import '../providers/posts_providers.dart';
import 'widgets/post_card.dart';

void _showSingleSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

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
  final FocusNode _commentFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _comments = [];
  final Set<String> _collapsedCommentIds = <String>{};
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

  String? _replyToCommentId;
  String? _replyToName;

  void _setReplyTarget(String commentId, String name) {
    setState(() {
      _replyToCommentId = commentId;
      _replyToName = name;
    });
    _commentFocusNode.requestFocus();
    _commentController.selection = TextSelection.collapsed(
      offset: _commentController.text.length,
    );
  }

  Future<void> _sendComment() async {
    final String content = _commentController.text.trim();
    if (content.isEmpty) return;
    setState(() {
      _sending = true;
      _commentError = null;
    });
    _commentController.clear();
    final parentId = _replyToCommentId;
    _replyToCommentId = null;
    _replyToName = null;
    setState(() {});
    try {
      final repo = ref.read(socialRepositoryProvider);
      final Map<String, dynamic> comment = await repo.addComment(
        widget.postId,
        content,
        parentCommentId: parentId,
      );
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

  void _removeComment(String commentId) {
    final ids = _collectSubtreeIds(commentId);
    setState(() {
      _collapsedCommentIds.removeWhere(ids.contains);
      _comments.removeWhere((c) => ids.contains(c['id']?.toString()));
    });
  }

  void _replaceComment(String commentId, Map<String, dynamic> updated) {
    final idx = _comments.indexWhere((c) => c['id'] == commentId);
    if (idx >= 0) setState(() => _comments[idx] = updated);
  }

  Set<String> _collectSubtreeIds(String rootId) {
    final ids = <String>{rootId};
    bool changed = true;
    while (changed) {
      changed = false;
      for (final c in _comments) {
        final id = c['id']?.toString();
        final parentId = c['parent_id']?.toString();
        if (id == null || id.isEmpty || parentId == null || parentId.isEmpty)
          continue;
        if (ids.contains(parentId) && !ids.contains(id)) {
          ids.add(id);
          changed = true;
        }
      }
    }
    return ids;
  }

  void _toggleCollapse(String commentId) {
    setState(() {
      if (_collapsedCommentIds.contains(commentId)) {
        _collapsedCommentIds.remove(commentId);
      } else {
        _collapsedCommentIds.add(commentId);
      }
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
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
                  postId: widget.postId,
                  comments: _comments,
                  loadingComments: _loadingComments,
                  commentError: _commentError,
                  scrollController: _scrollController,
                  onRefresh: _loadComments,
                  onPostDeleted: () => context.pop(),
                  replyToName: _replyToName,
                  onReplyTarget: _setReplyTarget,
                  onCommentDeleted: _removeComment,
                  onCommentUpdated: _replaceComment,
                  collapsedIds: _collapsedCommentIds,
                  onToggleCollapse: _toggleCollapse,
                  ref: ref,
                );
              },
              loading: () {
                if (widget.initialPost != null) {
                  return _DetailContent(
                    post: widget.initialPost!,
                    postId: widget.postId,
                    comments: _comments,
                    loadingComments: _loadingComments,
                    commentError: _commentError,
                    scrollController: _scrollController,
                    onRefresh: _loadComments,
                    onPostDeleted: () => context.pop(),
                    replyToName: _replyToName,
                    onReplyTarget: _setReplyTarget,
                    onCommentDeleted: _removeComment,
                    onCommentUpdated: _replaceComment,
                    collapsedIds: _collapsedCommentIds,
                    onToggleCollapse: _toggleCollapse,
                    ref: ref,
                  );
                }
                return const Center(child: CircularProgressIndicator());
              },
              error: (_, __) {
                if (widget.initialPost != null) {
                  return _DetailContent(
                    post: widget.initialPost!,
                    postId: widget.postId,
                    comments: _comments,
                    loadingComments: _loadingComments,
                    commentError: _commentError,
                    scrollController: _scrollController,
                    onRefresh: _loadComments,
                    onPostDeleted: () => context.pop(),
                    replyToName: _replyToName,
                    onReplyTarget: _setReplyTarget,
                    onCommentDeleted: _removeComment,
                    onCommentUpdated: _replaceComment,
                    collapsedIds: _collapsedCommentIds,
                    onToggleCollapse: _toggleCollapse,
                    ref: ref,
                  );
                }
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Text('加载失败'),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(postDetailProvider(widget.postId)),
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
            focusNode: _commentFocusNode,
            isSending: _sending,
            onSend: _sendComment,
            bottomPadding: bottomPadding,
            replyToName: _replyToName,
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
    required this.postId,
    required this.comments,
    required this.loadingComments,
    this.commentError,
    required this.scrollController,
    required this.onRefresh,
    this.onPostDeleted,
    this.replyToName,
    required this.onReplyTarget,
    required this.onCommentDeleted,
    required this.onCommentUpdated,
    required this.collapsedIds,
    required this.onToggleCollapse,
    required this.ref,
  });

  final PostModel post;
  final String postId;
  final List<Map<String, dynamic>> comments;
  final bool loadingComments;
  final String? commentError;
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;
  final VoidCallback? onPostDeleted;
  final String? replyToName;
  final void Function(String commentId, String name) onReplyTarget;
  final void Function(String commentId) onCommentDeleted;
  final void Function(String commentId, Map<String, dynamic> updated)
  onCommentUpdated;
  final Set<String> collapsedIds;
  final void Function(String commentId) onToggleCollapse;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final roots = _buildDetailCommentTree(comments);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: LayoutConstants.kContentMaxWidthWide,
        ),
        child: RefreshIndicator(
          onRefresh: onRefresh,
          child: CustomScrollView(
            controller: scrollController,
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: PostCard(
                  post: post,
                  isDetailView: true,
                  onPostDeleted: onPostDeleted,
                ),
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
              const SliverToBoxAdapter(
                child: Divider(height: 1, thickness: 0.5),
              ),
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
                    (_, int i) => _DetailCommentTreeItem(
                      node: roots[i],
                      postId: postId,
                      authUserId: ref.watch(authStateProvider).valueOrNull?.id,
                      onReply: onReplyTarget,
                      onDeleted: onCommentDeleted,
                      onUpdated: onCommentUpdated,
                      collapsedIds: collapsedIds,
                      onToggleCollapse: onToggleCollapse,
                    ),
                    childCount: roots.length,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailCommentNode {
  const _DetailCommentNode({required this.comment, required this.children});
  final Map<String, dynamic> comment;
  final List<_DetailCommentNode> children;
}

List<_DetailCommentNode> _buildDetailCommentTree(
  List<Map<String, dynamic>> comments,
) {
  final nodes = <String, _DetailCommentNode>{};
  for (final c in comments) {
    final id = c['id']?.toString();
    if (id == null || id.isEmpty) continue;
    nodes[id] = _DetailCommentNode(
      comment: c,
      children: <_DetailCommentNode>[],
    );
  }
  final roots = <_DetailCommentNode>[];
  for (final c in comments) {
    final id = c['id']?.toString();
    if (id == null || id.isEmpty) continue;
    final node = nodes[id];
    if (node == null) continue;
    final parentId = c['parent_id']?.toString();
    if (parentId != null &&
        parentId.isNotEmpty &&
        nodes.containsKey(parentId)) {
      nodes[parentId]!.children.add(node);
    } else {
      roots.add(node);
    }
  }
  return roots;
}

/// 详情页评论树节点：支持层级、折叠、本人可编辑/删除。
class _DetailCommentTreeItem extends ConsumerWidget {
  const _DetailCommentTreeItem({
    required this.node,
    required this.postId,
    this.authUserId,
    required this.onReply,
    required this.onDeleted,
    required this.onUpdated,
    required this.collapsedIds,
    required this.onToggleCollapse,
    this.depth = 0,
  });

  final _DetailCommentNode node;
  final String postId;
  final String? authUserId;
  final void Function(String commentId, String name) onReply;
  final void Function(String commentId) onDeleted;
  final void Function(String commentId, Map<String, dynamic> updated) onUpdated;
  final Set<String> collapsedIds;
  final void Function(String commentId) onToggleCollapse;
  final int depth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comment = node.comment;
    final children = node.children;
    final Map<String, dynamic>? user = comment['user'] is Map
        ? comment['user'] as Map<String, dynamic>
        : null;
    final String name =
        user?['display_name'] as String? ??
        user?['username'] as String? ??
        comment['display_name']?.toString() ??
        comment['username']?.toString() ??
        '未知用户';
    final String? avatarUrl = user?['avatar_url'] as String?;
    final String content = comment['content']?.toString() ?? '';
    final String commentId = comment['id']?.toString() ?? '';
    final bool isOwn =
        authUserId != null && comment['user_id']?.toString() == authUserId;
    final bool hasChildren = children.isNotEmpty;
    final bool collapsed = hasChildren && collapsedIds.contains(commentId);

    return Container(
      margin: EdgeInsets.fromLTRB(16 + depth * 14.0, 6, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CommentAvatar(name: name, avatarUrl: avatarUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            name,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (hasChildren)
                          TextButton(
                            onPressed: () => onToggleCollapse(commentId),
                            child: Text(
                              collapsed ? '展开 ${children.length} 条回复' : '收起回复',
                            ),
                          ),
                        if (isOwn)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 18),
                            padding: EdgeInsets.zero,
                            onSelected: (String value) async {
                              if (value == 'edit') {
                                final controller = TextEditingController(
                                  text: content,
                                );
                                final result = await showDialog<String>(
                                  context: context,
                                  builder: (BuildContext ctx) => AlertDialog(
                                    title: const Text('编辑评论'),
                                    content: TextField(
                                      controller: controller,
                                      maxLines: 3,
                                      autofocus: true,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    actions: <Widget>[
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(
                                          ctx,
                                          controller.text.trim(),
                                        ),
                                        child: const Text('保存'),
                                      ),
                                    ],
                                  ),
                                );
                                if (result != null &&
                                    result.isNotEmpty &&
                                    context.mounted) {
                                  try {
                                    final repo = ref.read(
                                      socialRepositoryProvider,
                                    );
                                    final updated = await repo.updateComment(
                                      postId,
                                      commentId,
                                      result,
                                    );
                                    onUpdated(commentId, <String, dynamic>{
                                      ...comment,
                                      ...updated,
                                    });
                                    if (context.mounted) {
                                      _showSingleSnackBar(context, '已保存');
                                    }
                                  } catch (err) {
                                    final msg = err
                                        .toString()
                                        .replaceFirst('Exception: ', '')
                                        .trim();
                                    if (context.mounted) {
                                      _showSingleSnackBar(
                                        context,
                                        msg.isNotEmpty ? msg : '编辑失败，请重试',
                                      );
                                    }
                                  }
                                }
                              } else if (value == 'delete') {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (BuildContext ctx) => AlertDialog(
                                    title: const Text('删除评论'),
                                    content: const Text(
                                      '确定要删除这条评论吗？其回复也会一并删除。',
                                    ),
                                    actions: <Widget>[
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Theme.of(
                                            ctx,
                                          ).colorScheme.error,
                                        ),
                                        child: const Text('删除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && context.mounted) {
                                  try {
                                    final repo = ref.read(
                                      socialRepositoryProvider,
                                    );
                                    await repo.deleteComment(postId, commentId);
                                    onDeleted(commentId);
                                    if (context.mounted) {
                                      _showSingleSnackBar(context, '已删除');
                                    }
                                  } catch (err) {
                                    final msg = err
                                        .toString()
                                        .replaceFirst('Exception: ', '')
                                        .trim();
                                    if (context.mounted) {
                                      _showSingleSnackBar(
                                        context,
                                        msg.isNotEmpty ? msg : '删除失败，请重试',
                                      );
                                    }
                                  }
                                }
                              }
                            },
                            itemBuilder: (BuildContext context) =>
                                <PopupMenuEntry<String>>[
                                  const PopupMenuItem<String>(
                                    value: 'edit',
                                    child: Text('编辑'),
                                  ),
                                  const PopupMenuItem<String>(
                                    value: 'delete',
                                    child: Text('删除'),
                                  ),
                                ],
                          ),
                      ],
                    ),
                    Text(
                      content,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => onReply(commentId, name),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('回复'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!collapsed && hasChildren)
            Column(
              children: children
                  .map(
                    (child) => _DetailCommentTreeItem(
                      node: child,
                      postId: postId,
                      authUserId: authUserId,
                      onReply: onReply,
                      onDeleted: onDeleted,
                      onUpdated: onUpdated,
                      collapsedIds: collapsedIds,
                      onToggleCollapse: onToggleCollapse,
                      depth: depth + 1,
                    ),
                  )
                  .toList(),
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
    required this.focusNode,
    required this.isSending,
    required this.onSend,
    required this.bottomPadding,
    this.replyToName,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final VoidCallback onSend;
  final double bottomPadding;
  final String? replyToName;

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
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: replyToName != null ? '回复 @$replyToName' : '写评论...',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
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
