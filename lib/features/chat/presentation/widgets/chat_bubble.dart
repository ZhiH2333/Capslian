import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/chat_repository.dart';
import '../../data/models/sn_chat_message.dart';

/// 单条消息气泡：文本 / 图片 / 已撤回。
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onLongPress,
  });

  final SnChatMessage message;
  final bool isMe;
  final void Function(SnChatMessage message)? onLongPress;

  static String _formatTime(String? createdAt) {
    if (createdAt == null || createdAt.isEmpty) return '';
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) return '';
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) {
      return _buildDeleted(context);
    }
    final hasImage = message.attachments.any((a) => a.isImage);
    if (hasImage) {
      return _buildImage(context);
    }
    return _buildText(context);
  }

  Widget _buildDeleted(BuildContext context) {
    final theme = Theme.of(context);
    final time = _formatTime(message.createdAt);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '消息已撤回',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (time.isNotEmpty)
              Text(
                time,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildText(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isMe ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
    final fg = isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant;
    final time = _formatTime(message.createdAt);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress != null ? () => onLongPress!(message) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  message.content,
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                ),
              ),
              if (time.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  time,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    final theme = Theme.of(context);
    final time = _formatTime(message.createdAt);
    final imageAttachments = message.attachments.where((a) => a.isImage).toList();
    final firstUrl = imageAttachments.isNotEmpty
        ? ChatRepository.imageUrl(imageAttachments.first.url)
        : '';
    final isNetwork = firstUrl.isNotEmpty;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress != null ? () => onLongPress!(message) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: isNetwork
                    ? CachedNetworkImage(
                        imageUrl: firstUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const _ImagePlaceholder(text: '加载中...'),
                        errorWidget: (_, __, ___) =>
                            const _ImagePlaceholder(text: '图片加载失败'),
                      )
                    : const _ImagePlaceholder(text: '图片上传中...'),
              ),
              if (message.content.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  message.content,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (time.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  time,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 140,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
