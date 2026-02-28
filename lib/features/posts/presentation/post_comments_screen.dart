import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../../auth/providers/auth_providers.dart';
import '../../social/providers/social_providers.dart';

void _showSingleSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

/// 帖子评论列表与发表。
class PostCommentsScreen extends ConsumerStatefulWidget {
  const PostCommentsScreen({super.key, required this.postId});
  final String postId;

  @override
  ConsumerState<PostCommentsScreen> createState() => _PostCommentsScreenState();
}

class _PostCommentsScreenState extends ConsumerState<PostCommentsScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final List<Map<String, dynamic>> _comments = [];
  final Set<String> _collapsedCommentIds = <String>{};
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(socialRepositoryProvider);
      final list = await repo.getComments(widget.postId);
      if (mounted) {
        setState(() {
          _comments.clear();
          _comments.addAll(list);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _send({String? parentCommentId}) async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    _controller.clear();
    _replyToCommentId = null;
    _replyToName = null;
    try {
      final repo = ref.read(socialRepositoryProvider);
      final comment = await repo.addComment(
        widget.postId,
        content,
        parentCommentId: parentCommentId,
      );
      if (mounted) {
        setState(() {
          _comments.insert(0, comment);
          _sending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _sending = false;
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
    _inputFocusNode.requestFocus();
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
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

  List<_CommentNode> _buildCommentTree() {
    final nodes = <String, _CommentNode>{};
    for (final c in _comments) {
      final id = c['id']?.toString();
      if (id == null || id.isEmpty) continue;
      nodes[id] = _CommentNode(comment: c, children: <_CommentNode>[]);
    }
    final roots = <_CommentNode>[];
    for (final c in _comments) {
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

  @override
  void dispose() {
    _controller.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding =
        MediaQuery.paddingOf(context).bottom + LayoutConstants.kSpacingLarge;
    final authUserId = ref.watch(authStateProvider).valueOrNull?.id;
    final roots = _buildCommentTree();
    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: const Text('评论'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: LayoutConstants.kContentMaxWidthWide,
                      ),
                      child: ListView.builder(
                        padding: EdgeInsets.only(bottom: bottomPadding),
                        itemCount: roots.length,
                        itemBuilder: (_, int i) {
                          final node = roots[i];
                          return _CommentTreeItem(
                            node: node,
                            postId: widget.postId,
                            authUserId: authUserId,
                            onReply: _setReplyTarget,
                            onDeleted: _removeComment,
                            onUpdated: _replaceComment,
                            collapsedIds: _collapsedCommentIds,
                            onToggleCollapse: _toggleCollapse,
                          );
                        },
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(LayoutConstants.kSpacingSmall),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: LayoutConstants.kContentMaxWidthWide,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _inputFocusNode,
                        decoration: InputDecoration(
                          hintText: _replyToName != null
                              ? '回复 @$_replyToName'
                              : '写评论...',
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) =>
                            _send(parentCommentId: _replyToCommentId),
                      ),
                    ),
                    IconButton(
                      onPressed: _sending
                          ? null
                          : () => _send(parentCommentId: _replyToCommentId),
                      icon: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentNode {
  const _CommentNode({required this.comment, required this.children});
  final Map<String, dynamic> comment;
  final List<_CommentNode> children;
}

/// 评论树节点：支持层级、折叠、本人编辑/删除。
class _CommentTreeItem extends ConsumerWidget {
  const _CommentTreeItem({
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

  final _CommentNode node;
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
    final user = comment['user'] is Map
        ? comment['user'] as Map<String, dynamic>
        : null;
    final name =
        user?['display_name'] ??
        user?['username'] ??
        comment['display_name']?.toString() ??
        comment['username']?.toString() ??
        '?';
    final String commentId = comment['id']?.toString() ?? '';
    final bool isOwn =
        authUserId != null && comment['user_id']?.toString() == authUserId;
    final bool hasChildren = children.isNotEmpty;
    final bool collapsed = hasChildren && collapsedIds.contains(commentId);
    final bgColor = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);

    return Container(
      margin: EdgeInsets.fromLTRB(
        LayoutConstants.kSpacingSmall + depth * 14.0,
        6,
        LayoutConstants.kSpacingSmall,
        0,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (hasChildren)
                TextButton(
                  onPressed: () => onToggleCollapse(commentId),
                  child: Text(collapsed ? '展开 ${children.length} 条回复' : '收起回复'),
                ),
              if (isOwn)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  padding: EdgeInsets.zero,
                  onSelected: (String value) async {
                    if (value == 'edit') {
                      final controller = TextEditingController(
                        text: comment['content']?.toString() ?? '',
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
                              onPressed: () =>
                                  Navigator.pop(ctx, controller.text.trim()),
                              child: const Text('保存'),
                            ),
                          ],
                        ),
                      );
                      if (result != null &&
                          result.isNotEmpty &&
                          context.mounted) {
                        try {
                          final repo = ref.read(socialRepositoryProvider);
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
                          content: const Text('确定要删除这条评论吗？其回复也会一并删除。'),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
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
                          final repo = ref.read(socialRepositoryProvider);
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
            comment['content']?.toString() ?? '',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => onReply(commentId, name),
            child: const Text('回复'),
          ),
          if (!collapsed && hasChildren)
            Column(
              children: children
                  .map(
                    (child) => _CommentTreeItem(
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
