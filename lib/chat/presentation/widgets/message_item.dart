import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/models/local_chat_message.dart';

/// 消息操作类型。
enum MessageAction {
  reply,
  edit,
  delete,
  forward,
  resend,
}

/// 滑动显示时间戳的最大偏移量（px）。
const double _kMaxSlide = 72.0;

/// 右侧时间戳占位宽度（px，含秒后需要更宽）。
const double _kTimestampWidth = 80.0;

/// 格式化消息时间戳为 HH:mm:ss（含秒）。
String _formatTimestamp(String? iso) {
  if (iso == null) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final local = dt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}

/// 单条消息的完整 UI，包括气泡、发送者信息、状态、回复预览和反应。
class MessageItem extends StatelessWidget {
  const MessageItem({
    super.key,
    required this.message,
    required this.isCurrentUser,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.onAction,
    required this.slideOffsetNotifier,
  });

  final LocalChatMessage message;
  final bool isCurrentUser;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final void Function(MessageAction action, LocalChatMessage message) onAction;

  /// 列表层传入的水平滑动偏移，用于 iMessage 风格的时间戳显示。
  final ValueNotifier<double> slideOffsetNotifier;

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) {
      return _DeletedMessageBubble(
        isCurrentUser: isCurrentUser,
        isLastInGroup: isLastInGroup,
      );
    }
    return ValueListenableBuilder<double>(
      valueListenable: slideOffsetNotifier,
      builder: (BuildContext ctx, double offset, Widget? child) {
        return LayoutBuilder(
          builder: (BuildContext lctx, BoxConstraints constraints) {
            return ClipRect(
              child: SizedBox(
                width: constraints.maxWidth,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    // 时间戳：初始在右侧屏幕外，向左滑动后逐渐显现
                    Positioned(
                      right: -_kTimestampWidth + offset,
                      top: 0,
                      bottom: 0,
                      child: SizedBox(
                        width: _kTimestampWidth,
                        child: Center(
                          child: Opacity(
                            opacity: (offset / _kMaxSlide).clamp(0.0, 1.0),
                            child: Text(
                              _formatTimestamp(message.createdAt),
                              style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 消息内容：向左平移
                    Transform.translate(
                      offset: Offset(-offset, 0),
                      child: child,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      child: GestureDetector(
        onLongPress: () => _showActionMenu(context),
        child: Padding(
          padding: EdgeInsets.only(
            left: isCurrentUser ? 48 : 12,
            right: isCurrentUser ? 12 : 48,
            top: isFirstInGroup ? 8 : 2,
            bottom: isLastInGroup ? 4 : 0,
          ),
          child: Row(
            mainAxisAlignment:
                isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              if (!isCurrentUser) _buildAvatar(context),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: isCurrentUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: <Widget>[
                    if (!isCurrentUser && isFirstInGroup)
                      _buildSenderName(context),
                    if (message.replyMessage != null)
                      _ReplyPreview(replyMessage: message.replyMessage!),
                    _buildBubble(context),
                    if (message.reactions.isNotEmpty)
                      _ReactionsRow(reactions: message.reactions),
                    if (isLastInGroup)
                      _MessageFooter(
                        message: message,
                        isCurrentUser: isCurrentUser,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    if (!isLastInGroup) {
      return const SizedBox(width: 32);
    }
    final sender = message.sender;
    final name = sender?.name ?? message.senderId;
    final avatarUrl = sender?.avatarUrl;
    return CircleAvatar(
      radius: 16,
      backgroundImage:
          avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      child: avatarUrl == null
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 12),
            )
          : null,
    );
  }

  Widget _buildSenderName(BuildContext context) {
    final name = message.sender?.name ?? message.senderId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, left: 2),
      child: Text(
        name,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildBubble(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: isCurrentUser || !isLastInGroup
              ? const Radius.circular(16)
              : const Radius.circular(4),
          bottomRight: !isCurrentUser || !isLastInGroup
              ? const Radius.circular(16)
              : const Radius.circular(4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.content.isNotEmpty) Text(message.content),
          if (message.attachments.isNotEmpty)
            _AttachmentList(attachments: message.attachments),
        ],
      ),
    );
  }

  void _showActionMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => _MessageActionSheet(
        message: message,
        isCurrentUser: isCurrentUser,
        onAction: onAction,
      ),
    );
  }
}

/// 已删除消息占位气泡。
class _DeletedMessageBubble extends StatelessWidget {
  const _DeletedMessageBubble({
    required this.isCurrentUser,
    required this.isLastInGroup,
  });

  final bool isCurrentUser;
  final bool isLastInGroup;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isCurrentUser ? 48 : 12,
        right: isCurrentUser ? 12 : 48,
        top: 2,
        bottom: isLastInGroup ? 4 : 0,
      ),
      child: Align(
        alignment:
            isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            '消息已撤回',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ),
      ),
    );
  }
}

/// 回复预览条。
class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.replyMessage});

  final LocalChatMessage replyMessage;

  @override
  Widget build(BuildContext context) {
    final senderName = replyMessage.sender?.name ?? replyMessage.senderId;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            senderName,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          Text(
            replyMessage.isDeleted
                ? '消息已撤回'
                : (replyMessage.content.isNotEmpty
                    ? replyMessage.content
                    : '[附件]'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

/// 消息附件列表（图片直接展示，文件显示文件名）。
class _AttachmentList extends StatelessWidget {
  const _AttachmentList({required this.attachments});

  final List<dynamic> attachments;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: attachments.map((dynamic a) {
        if (a.isImage == true) {
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: a.url as String,
                width: 200,
                fit: BoxFit.cover,
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.attach_file, size: 16),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  a.name as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// 消息底部：时间 + 发送状态。
class _MessageFooter extends StatelessWidget {
  const _MessageFooter({
    required this.message,
    required this.isCurrentUser,
  });

  final LocalChatMessage message;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatTime(message.createdAt);
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 2, right: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            timeStr,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (isCurrentUser) ...[
            const SizedBox(width: 4),
            _StatusIcon(status: message.status),
          ],
        ],
      ),
    );
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }
}

/// 发送状态图标。
class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final MessageStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == MessageStatus.pending) {
      return Icon(
        Icons.schedule,
        size: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    if (status == MessageStatus.failed) {
      return Icon(
        Icons.error_outline,
        size: 12,
        color: Theme.of(context).colorScheme.error,
      );
    }
    return Icon(
      Icons.done,
      size: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

/// 消息反应行（每种 emoji + 数量）。
class _ReactionsRow extends StatelessWidget {
  const _ReactionsRow({required this.reactions});

  final Map<String, List<String>> reactions;

  @override
  Widget build(BuildContext context) {
    final entries = reactions.entries
        .where((e) => e.value.isNotEmpty)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: entries.map((MapEntry<String, List<String>> e) {
          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Text(
              '${e.key} ${e.value.length}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 消息操作底部弹窗。
class _MessageActionSheet extends StatelessWidget {
  const _MessageActionSheet({
    required this.message,
    required this.isCurrentUser,
    required this.onAction,
  });

  final LocalChatMessage message;
  final bool isCurrentUser;
  final void Function(MessageAction action, LocalChatMessage message) onAction;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('回复'),
            onTap: () {
              Navigator.pop(context);
              onAction(MessageAction.reply, message);
            },
          ),
          ListTile(
            leading: const Icon(Icons.forward),
            title: const Text('转发'),
            onTap: () {
              Navigator.pop(context);
              onAction(MessageAction.forward, message);
            },
          ),
          if (isCurrentUser) ...[
            if (!message.isDeleted)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('编辑'),
                onTap: () {
                  Navigator.pop(context);
                  onAction(MessageAction.edit, message);
                },
              ),
            if (message.isFailed)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('重新发送'),
                onTap: () {
                  Navigator.pop(context);
                  onAction(MessageAction.resend, message);
                },
              ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '撤回',
                style:
                    TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(context);
                onAction(MessageAction.delete, message);
              },
            ),
          ],
        ],
      ),
    );
  }
}
