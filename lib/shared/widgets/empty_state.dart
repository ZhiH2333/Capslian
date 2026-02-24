import 'package:flutter/material.dart';

import '../../core/constants/layout_constants.dart';

/// 统一空状态：图标、标题、描述、可选操作按钮。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.description,
    this.icon,
    this.action,
  });

  final String title;
  final String description;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconData = icon ?? Icons.inbox_outlined;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LayoutConstants.kSpacingXLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              iconData,
              size: 64,
              color: colorScheme.outline,
            ),
            const SizedBox(height: LayoutConstants.kSpacingLarge),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LayoutConstants.kSpacingSmall),
            Text(
              description,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: LayoutConstants.kSpacingXLarge),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
