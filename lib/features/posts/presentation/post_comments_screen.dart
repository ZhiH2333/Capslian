import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../../auth/providers/auth_providers.dart';
import '../../social/providers/social_providers.dart';

/// 帖子评论列表与发表。
class PostCommentsScreen extends ConsumerStatefulWidget {
  const PostCommentsScreen({super.key, required this.postId});
  final String postId;

  @override
  ConsumerState<PostCommentsScreen> createState() => _PostCommentsScreenState();
}

class _PostCommentsScreenState extends ConsumerState<PostCommentsScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _comments = [];
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
  }

  void _removeComment(String commentId) {
    setState(() => _comments.removeWhere((c) => c['id'] == commentId));
  }

  void _replaceComment(String commentId, Map<String, dynamic> updated) {
    final idx = _comments.indexWhere((c) => c['id'] == commentId);
    if (idx >= 0) setState(() => _comments[idx] = updated);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom + LayoutConstants.kSpacingLarge;
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
                          constraints: const BoxConstraints(maxWidth: LayoutConstants.kContentMaxWidthWide),
                          child: ListView.builder(
                            padding: EdgeInsets.only(bottom: bottomPadding),
                            itemCount: _comments.length,
                            itemBuilder: (_, int i) {
                              final c = _comments[i];
                              return _CommentRow(
                                comment: c,
                                postId: widget.postId,
                                authUserId: ref.watch(authStateProvider).valueOrNull?.id,
                                onReply: _setReplyTarget,
                                onDeleted: _removeComment,
                                onUpdated: _replaceComment,
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
                constraints: const BoxConstraints(maxWidth: LayoutConstants.kContentMaxWidthWide),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: _replyToName != null ? '回复 @$_replyToName' : '写评论...',
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _send(parentCommentId: _replyToCommentId),
                      ),
                    ),
                    IconButton(
                      onPressed: _sending ? null : () => _send(parentCommentId: _replyToCommentId),
                      icon: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
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

/// 单条评论：显示内容、回复按钮，本人评论显示编辑/删除菜单。
class _CommentRow extends ConsumerWidget {
  const _CommentRow({
    required this.comment,
    required this.postId,
    this.authUserId,
    required this.onReply,
    required this.onDeleted,
    required this.onUpdated,
  });

  final Map<String, dynamic> comment;
  final String postId;
  final String? authUserId;
  final void Function(String commentId, String name) onReply;
  final void Function(String commentId) onDeleted;
  final void Function(String commentId, Map<String, dynamic> updated) onUpdated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = comment['user'] is Map ? comment['user'] as Map<String, dynamic> : null;
    final name = user?['display_name'] ?? user?['username'] ?? comment['display_name']?.toString() ?? comment['username']?.toString() ?? '?';
    final String commentId = comment['id']?.toString() ?? '';
    final bool isOwn = authUserId != null && comment['user_id']?.toString() == authUserId;
    final String? parentId = comment['parent_id']?.toString();
    return ListTile(
      contentPadding: LayoutConstants.kListTileContentPadding,
      title: Row(
        children: <Widget>[
          Expanded(child: Text(name)),
          TextButton(
            onPressed: () => onReply(commentId, name),
            child: const Text('回复'),
          ),
          if (isOwn)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              padding: EdgeInsets.zero,
              onSelected: (String value) async {
                if (value == 'edit') {
                  final controller = TextEditingController(text: comment['content']?.toString() ?? '');
                  final result = await showDialog<String>(
                    context: context,
                    builder: (BuildContext ctx) => AlertDialog(
                      title: const Text('编辑评论'),
                      content: TextField(
                        controller: controller,
                        maxLines: 3,
                        autofocus: true,
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  );
                  if (result != null && result.isNotEmpty && context.mounted) {
                    try {
                      final repo = ref.read(socialRepositoryProvider);
                      final updated = await repo.updateComment(postId, commentId, result);
                      onUpdated(commentId, updated);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('编辑失败，请重试')));
                      }
                    }
                  }
                } else if (value == 'delete') {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (BuildContext ctx) => AlertDialog(
                      title: const Text('删除评论'),
                      content: const Text('确定要删除这条评论吗？'),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(ctx).colorScheme.error,
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
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除')));
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
                      }
                    }
                  }
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(value: 'edit', child: Text('编辑')),
                const PopupMenuItem<String>(value: 'delete', child: Text('删除')),
              ],
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (parentId != null && parentId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '回复',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          Text(comment['content']?.toString() ?? ''),
        ],
      ),
    );
  }
}
