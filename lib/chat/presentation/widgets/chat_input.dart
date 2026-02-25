import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_provider.dart';
import '../../data/models/local_chat_message.dart';
import '../../data/models/sn_chat_message.dart';
import '../../pods/messages_notifier.dart';

/// 聊天输入区，支持文本、图片附件、回复和编辑模式。
class ChatInput extends ConsumerStatefulWidget {
  const ChatInput({
    super.key,
    required this.roomId,
    this.replyingTo,
    this.editingTo,
    this.onClearReply,
    this.onClearEdit,
  });

  final String roomId;
  final LocalChatMessage? replyingTo;
  final LocalChatMessage? editingTo;
  final VoidCallback? onClearReply;
  final VoidCallback? onClearEdit;

  @override
  ConsumerState<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends ConsumerState<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final List<XFile> _pendingFiles = [];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    if (widget.editingTo != null) {
      _controller.text = widget.editingTo!.content;
    }
  }

  @override
  void didUpdateWidget(ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editingTo != oldWidget.editingTo) {
      if (widget.editingTo != null) {
        _controller.text = widget.editingTo!.content;
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      } else if (oldWidget.editingTo != null) {
        _controller.clear();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _pendingFiles.add(file));
  }

  Future<SnChatAttachment?> _uploadFile(XFile file) async {
    try {
      final dio = ref.read(dioProvider);
      final formData = FormData();
      formData.files.add(MapEntry(
        'file',
        await MultipartFile.fromFile(file.path, filename: file.name),
      ));
      final response = await dio.post<Map<String, dynamic>>(
        ApiConstants.upload,
        data: formData,
      );
      final url = response.data?['url'] as String?;
      if (url == null) return null;
      return SnChatAttachment(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: file.name,
        url: url,
        mimeType: file.mimeType,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    final hasContent = content.isNotEmpty || _pendingFiles.isNotEmpty;
    if (!hasContent || _isSending) return;
    setState(() => _isSending = true);
    try {
      final attachments = <SnChatAttachment>[];
      for (final file in _pendingFiles) {
        final uploaded = await _uploadFile(file);
        if (uploaded != null) attachments.add(uploaded);
      }
      await ref.read(messagesProvider(widget.roomId).notifier).sendMessage(
            content,
            attachments,
            replyingTo: widget.replyingTo,
            editingTo: widget.editingTo,
          );
      _controller.clear();
      setState(() => _pendingFiles.clear());
      widget.onClearReply?.call();
      widget.onClearEdit?.call();
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.replyingTo != null) _ReplyBar(
          message: widget.replyingTo!,
          onClose: () => widget.onClearReply?.call(),
        ),
        if (widget.editingTo != null) _EditBar(
          onClose: () => widget.onClearEdit?.call(),
        ),
        if (_pendingFiles.isNotEmpty) _AttachmentPreviewRow(
          files: _pendingFiles,
          onRemove: (int index) => setState(() => _pendingFiles.removeAt(index)),
        ),
        _InputRow(
          controller: _controller,
          isSending: _isSending,
          onPickImage: _pickImage,
          onSend: _send,
        ),
      ],
    );
  }
}

/// 回复预览条。
class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.message, required this.onClose});

  final LocalChatMessage message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final senderName = message.sender?.name ?? message.senderId;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '回复 $senderName',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  message.content.isNotEmpty ? message.content : '[附件]',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// 编辑模式提示条。
class _EditBar extends StatelessWidget {
  const _EditBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Row(
        children: [
          Icon(
            Icons.edit,
            size: 16,
            color: Theme.of(context).colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '正在编辑消息',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// 待上传附件预览行。
class _AttachmentPreviewRow extends StatelessWidget {
  const _AttachmentPreviewRow({
    required this.files,
    required this.onRemove,
  });

  final List<XFile> files;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: files.length,
        itemBuilder: (_, int i) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.image, size: 32),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => onRemove(i),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部输入行（附件按钮 + 文本框 + 发送按钮）。
class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.controller,
    required this.isSending,
    required this.onPickImage,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onPickImage;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.image_outlined),
            onPressed: onPickImage,
            tooltip: '发送图片',
          ),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '输入消息...',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
            ),
          ),
          const SizedBox(width: 8),
          isSending
              ? const SizedBox(
                  width: 40,
                  height: 40,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: onSend,
                  tooltip: '发送',
                ),
        ],
      ),
    );
  }
}
