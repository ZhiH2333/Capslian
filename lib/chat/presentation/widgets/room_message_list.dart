import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/local_chat_message.dart';
import '../../pods/messages_notifier.dart';
import 'message_item.dart';

/// 消息列表，支持分页加载、时间分组标题。
class RoomMessageList extends ConsumerStatefulWidget {
  const RoomMessageList({
    super.key,
    required this.roomId,
    required this.currentUserId,
    required this.messages,
    required this.onAction,
  });

  final String roomId;
  final String currentUserId;
  final List<LocalChatMessage> messages;
  final void Function(MessageAction action, LocalChatMessage message) onAction;

  @override
  ConsumerState<RoomMessageList> createState() => _RoomMessageListState();
}

class _RoomMessageListState extends ConsumerState<RoomMessageList> {
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didUpdateWidget(RoomMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != oldWidget.messages.length) {
      final isNearBottom = _isNearBottom();
      if (isNearBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.pixels >= pos.maxScrollExtent - 200;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels <= 100 && !_isLoadingMore) {
      _loadMoreMessages();
    }
    final shouldShow = !_isNearBottom();
    if (shouldShow != _showScrollToBottom) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  void _loadMoreMessages() {
    setState(() => _isLoadingMore = true);
    ref
        .read(messagesProvider(widget.roomId).notifier)
        .fetchMoreMessages()
        .whenComplete(() {
      if (mounted) setState(() => _isLoadingMore = false);
    });
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildGroupedItems(widget.messages);
    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (BuildContext ctx, int i) {
            if (_isLoadingMore && i == 0) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final index = _isLoadingMore ? i - 1 : i;
            final item = items[index];
            if (item.isDateHeader) {
              return _DateHeader(label: item.dateLabel!);
            }
            return MessageItem(
              key: ValueKey('msg-${item.message!.nonce ?? item.message!.id}'),
              message: item.message!,
              isCurrentUser: item.message!.senderId == widget.currentUserId,
              isFirstInGroup: item.isFirstInGroup,
              isLastInGroup: item.isLastInGroup,
              onAction: widget.onAction,
            );
          },
        ),
        if (_showScrollToBottom)
          Positioned(
            bottom: 8,
            right: 8,
            child: FloatingActionButton.small(
              onPressed: _scrollToBottom,
              child: const Icon(Icons.keyboard_arrow_down),
            ),
          ),
      ],
    );
  }
}

/// 时间分组标题。
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ),
    );
  }
}

/// 列表项：日期标题或消息。
class _ListItem {
  _ListItem.dateHeader(this.dateLabel)
      : message = null,
        isFirstInGroup = false,
        isLastInGroup = false;

  _ListItem.message(
    this.message, {
    required this.isFirstInGroup,
    required this.isLastInGroup,
  }) : dateLabel = null;

  final String? dateLabel;
  final LocalChatMessage? message;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  bool get isDateHeader => dateLabel != null;
}

/// 构建时间分组 + 消息发送者分组列表项。
List<_ListItem> _buildGroupedItems(List<LocalChatMessage> messages) {
  final result = <_ListItem>[];
  String? lastDateKey;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  for (int i = 0; i < messages.length; i++) {
    final m = messages[i];
    final prev = i > 0 ? messages[i - 1] : null;
    final next = i < messages.length - 1 ? messages[i + 1] : null;

    final dateKey = _extractDateKey(m.createdAt);
    final dateLabel = _buildDateLabel(m.createdAt, today, yesterday);
    if (dateKey != lastDateKey) {
      lastDateKey = dateKey;
      result.add(_ListItem.dateHeader(dateLabel));
    }

    final isSameGroupAsPrev = prev != null &&
        prev.senderId == m.senderId &&
        _withinGroupInterval(prev.createdAt, m.createdAt);
    final isSameGroupAsNext = next != null &&
        next.senderId == m.senderId &&
        _withinGroupInterval(m.createdAt, next.createdAt);

    result.add(_ListItem.message(
      m,
      isFirstInGroup: !isSameGroupAsPrev,
      isLastInGroup: !isSameGroupAsNext,
    ));
  }
  return result;
}

String _extractDateKey(String? iso) {
  if (iso == null || iso.isEmpty) return 'today';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final d = dt.toLocal();
  return '${d.year}-${d.month}-${d.day}';
}

String _buildDateLabel(
  String? iso,
  DateTime today,
  DateTime yesterday,
) {
  if (iso == null || iso.isEmpty) return '今天';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final local = dt.toLocal();
  final d = DateTime(local.year, local.month, local.day);
  if (d == today) return '今天';
  if (d == yesterday) return '昨天';
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

/// 两条消息是否在 3 分钟内（同一发送者分组阈值）。
bool _withinGroupInterval(String? a, String? b) {
  if (a == null || b == null) return false;
  final dtA = DateTime.tryParse(a);
  final dtB = DateTime.tryParse(b);
  if (dtA == null || dtB == null) return false;
  return dtB.difference(dtA).abs().inMinutes < 3;
}
