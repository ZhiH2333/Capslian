import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../auth/providers/auth_providers.dart';
import '../../social/providers/social_providers.dart';
import '../data/models/message_model.dart';
import '../providers/chat_providers.dart';

/// 与指定用户的私信聊天页（REST 初载 + WebSocket 实时接收 + 发送走 REST）。
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.peerUserId, this.peerDisplayName});
  final String peerUserId;
  final String? peerDisplayName;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _loadingOlder = false;
  bool _hasScrolledToBottomOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final me = ref.read(authStateProvider).valueOrNull;
      if (me != null) {
        ref.read(socialRepositoryProvider).markConversationRead(widget.peerUserId);
      }
    });
  }

  void _subscribeWs(WidgetRef ref, String peerUserId, String myId) {
    ref.listen(wsRawMessagesProvider, (Object? prev, AsyncValue<Map<String, dynamic>> next) {
      next.whenData((Map<String, dynamic> payload) {
        final type = payload['type'] as String?;
        if (type != 'message') return;
        final msg = payload['message'] as Map<String, dynamic>?;
        if (msg == null) return;
        final senderId = msg['sender_id']?.toString() ?? '';
        final receiverId = msg['receiver_id']?.toString() ?? '';
        final isForThisChat = (senderId == myId && receiverId == peerUserId) ||
            (receiverId == myId && senderId == peerUserId);
        if (!isForThisChat) return;
        ref.read(chatMessagesNotifierProvider(peerUserId).notifier).appendFromWs(MessageModel.fromJson(msg));
      });
    });
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    final me = ref.read(authStateProvider).valueOrNull;
    if (me == null) return;
    _controller.clear();
    final tempId = const Uuid().v4();
    final optimistic = MessageModel(
      id: tempId,
      senderId: me.id,
      receiverId: widget.peerUserId,
      content: content,
      createdAt: null,
      status: MessageStatus.sending,
    );
    final notifier = ref.read(chatMessagesNotifierProvider(widget.peerUserId).notifier);
    notifier.appendOptimistic(optimistic);
    try {
      final repo = ref.read(socialRepositoryProvider);
      final raw = await repo.sendMessage(widget.peerUserId, content);
      final serverMessage = MessageModel.fromJson(raw);
      if (mounted) notifier.replaceOrAppend(serverMessage, replaceTemporaryId: tempId);
    } catch (_) {
      if (mounted) notifier.markFailed(tempId);
    }
  }

  Future<void> _removeFriendAndPop() async {
    final displayName = widget.peerDisplayName?.trim().isNotEmpty == true
        ? widget.peerDisplayName!
        : widget.peerUserId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定删除好友「$displayName」吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(socialRepositoryProvider).removeFriend(widget.peerUserId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除好友')));
      context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      final Object? data = e.response?.data;
      final String? msg = data is Map<String, dynamic>
          ? (data['error'] as String?)
          : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg ?? '删除失败，请重试')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authStateProvider).valueOrNull;
    if (me == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('聊天')),
        body: const Center(child: Text('请先登录')),
      );
    }
    _subscribeWs(ref, widget.peerUserId, me.id);
    final messagesAsync = ref.watch(chatMessagesNotifierProvider(widget.peerUserId));
    final displayName = widget.peerDisplayName?.trim().isNotEmpty == true
        ? widget.peerDisplayName!
        : widget.peerUserId;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                displayName,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: <Widget>[
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (String value) {
              if (value == 'delete_friend') _removeFriendAndPop();
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'delete_friend',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.person_remove, size: 20),
                    const SizedBox(width: 12),
                    const Text('删除好友'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: messagesAsync.when(
              data: (List<MessageModel> list) {
                // 列表已按时间升序（早→晚），从上到下展示；对方消息左侧、我方消息右侧（与微信一致）。
                if (list.isEmpty) {
                  return const Center(child: Text('暂无消息，发一条开始聊天吧'));
                }
                final items = _buildTimeGroupedItems(list);
                if (!_hasScrolledToBottomOnce) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!_scrollController.hasClients || !mounted) return;
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                    if (mounted) setState(() => _hasScrolledToBottomOnce = true);
                  });
                }
                return NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification n) {
                    if (n is ScrollEndNotification &&
                        _scrollController.hasClients &&
                        _scrollController.offset <= 80 &&
                        !_loadingOlder &&
                        list.isNotEmpty) {
                      final oldest = list.first.createdAt;
                      if (oldest != null && oldest.isNotEmpty) {
                        _loadingOlder = true;
                        ref
                            .read(chatMessagesNotifierProvider(widget.peerUserId).notifier)
                            .loadOlder(widget.peerUserId, oldest)
                            .whenComplete(() {
                          if (mounted) setState(() => _loadingOlder = false);
                        });
                      }
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: items.length + (_loadingOlder ? 1 : 0),
                    itemBuilder: (_, int i) {
                      if (_loadingOlder && i == 0) {
                        return const Padding(
                          padding: EdgeInsets.all(8),
                          child: Center(child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                        );
                      }
                      final index = _loadingOlder ? i - 1 : i;
                      final item = items[index];
                      if (item.isHeader) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              item.dateLabel!,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        );
                      }
                      final m = item.message!;
                      final isMe = m.senderId == me.id;
                      return _MessageBubble(
                        message: m,
                        isMe: isMe,
                        showStatus: isMe,
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object err, StackTrace? _) => Center(child: Text('加载失败: $err')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Message to $displayName',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 时间分组单条：要么是日期标题，要么是消息。
class _ChatListItem {
  _ChatListItem.header(this.dateLabel) : message = null;
  _ChatListItem.message(this.message) : dateLabel = null;
  final String? dateLabel;
  final MessageModel? message;
  bool get isHeader => dateLabel != null;
}

List<_ChatListItem> _buildTimeGroupedItems(List<MessageModel> list) {
  final result = <_ChatListItem>[];
  String? lastDateKey;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  for (final m in list) {
    final createdAt = m.createdAt;
    String dateKey;
    String label;
    if (createdAt == null || createdAt.isEmpty) {
      dateKey = today.toIso8601String();
      label = '今天';
    } else {
      final dt = DateTime.tryParse(createdAt);
      if (dt == null) {
        dateKey = createdAt;
        label = createdAt;
      } else {
        final d = DateTime(dt.year, dt.month, dt.day);
        dateKey = d.toIso8601String();
        if (d == today) {
          label = '今天';
        } else if (d == yesterday) {
          label = '昨天';
        } else {
          label = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        }
      }
    }
    if (lastDateKey != dateKey) {
      lastDateKey = dateKey;
      result.add(_ChatListItem.header(label));
    }
    result.add(_ChatListItem.message(m));
  }
  return result;
}

/// 单条消息气泡：我方（isMe）靠右，对方靠左，与微信一致。
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showStatus,
  });

  final MessageModel message;
  final bool isMe;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    IconData? statusIcon;
    if (showStatus) {
      if (message.status == MessageStatus.sending) {
        statusIcon = Icons.schedule;
      } else if (message.status == MessageStatus.failed) {
        statusIcon = Icons.error_outline;
      } else {
        statusIcon = message.read ? Icons.done_all : Icons.done;
      }
    }
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMe
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(message.content),
            ),
            if (statusIcon != null) ...<Widget>[
              const SizedBox(width: 4),
              Icon(statusIcon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
  }
}
