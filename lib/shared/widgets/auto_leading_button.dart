import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 通用返回按钮：点击执行退栈，用于 AppBar.leading。
class AutoLeadingButton extends StatelessWidget {
  const AutoLeadingButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => context.pop(),
    );
  }
}
