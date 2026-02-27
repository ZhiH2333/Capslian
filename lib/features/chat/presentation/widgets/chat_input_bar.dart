import 'package:flutter/material.dart';

/// 聊天输入栏：文本框 + 发送按钮；可选图片按钮。
class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSendText,
    this.onSendImages,
    this.hintText = '输入消息',
  });

  final TextEditingController controller;
  final VoidCallback onSendText;
  final VoidCallback? onSendImages;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Material(
          elevation: 2,
          shadowColor: theme.shadowColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(24),
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: <Widget>[
                if (onSendImages != null)
                  IconButton(
                    onPressed: onSendImages,
                    icon: const Icon(Icons.image_outlined),
                  ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _trySend(),
                    decoration: InputDecoration(
                      hintText: hintText,
                      isDense: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: controller,
                  builder: (BuildContext context, Widget? child) {
                    final enabled = controller.text.trim().isNotEmpty;
                    return IconButton(
                      onPressed: enabled ? _trySend : null,
                      icon: const Icon(Icons.send),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _trySend() {
    if (controller.text.trim().isEmpty) return;
    onSendText();
  }
}
