import 'package:flutter/material.dart';

/// 底部弹层统一壳：标题行、关闭按钮、分割线、可滚动内容区。
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    this.actions,
    this.onClose,
    this.height,
    required this.child,
  });

  final Widget title;
  final List<Widget>? actions;
  final VoidCallback? onClose;
  final double? height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxH = height ?? screenHeight * 0.8;
    return Container(
      padding: viewInsets,
      constraints: BoxConstraints(maxHeight: maxH),
      child: SizedBox(
        height: maxH,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: DefaultTextStyle(
                      style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.5,
                          ),
                      child: title,
                    ),
                  ),
                  if (actions != null) ...actions!,
                  IconButton(
                    icon: const Icon(Icons.close),
                    iconSize: 36,
                    onPressed: onClose ?? () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
