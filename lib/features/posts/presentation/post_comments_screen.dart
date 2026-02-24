import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
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

  Future<void> _send() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    _controller.clear();
    try {
      final repo = ref.read(socialRepositoryProvider);
      final comment = await repo.addComment(widget.postId, content);
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
                              final user = c['user'] is Map ? c['user'] as Map<String, dynamic> : null;
                              final name = user?['display_name'] ?? user?['username'] ?? c['display_name']?.toString() ?? c['username']?.toString() ?? '?';
                              return ListTile(
                                contentPadding: LayoutConstants.kListTileContentPadding,
                                title: Text(name),
                                subtitle: Text(c['content']?.toString() ?? ''),
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
                        decoration: const InputDecoration(hintText: '写评论...', border: OutlineInputBorder()),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    IconButton(
                      onPressed: _sending ? null : _send,
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
