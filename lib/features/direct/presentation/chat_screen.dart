import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../social/providers/social_providers.dart';

/// 与指定用户的私信聊天页（REST 拉取与发送；WebSocket 实时推送为可选扩展）。
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.peerUserId});
  final String peerUserId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
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
      final list = await repo.getMessages(widget.peerUserId);
      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(list.reversed);
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
      final msg = await repo.sendMessage(widget.peerUserId, content);
      if (mounted) {
        setState(() {
          _messages.add(msg);
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
    final me = ref.watch(authStateProvider).valueOrNull;
    if (me == null) {
      return Scaffold(appBar: AppBar(title: const Text('聊天')), body: const Center(child: Text('请先登录')));
    }
    return Scaffold(
      appBar: AppBar(title: Text('与 ${widget.peerUserId} 聊天')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : ListView.builder(
                        itemCount: _messages.length,
                        itemBuilder: (_, int i) {
                          final m = _messages[i];
                          final senderId = m['sender_id']?.toString() ?? '';
                          final isMe = senderId == me.id;
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isMe ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(m['content']?.toString() ?? ''),
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(hintText: '输入消息...', border: OutlineInputBorder()),
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
        ],
      ),
    );
  }
}
