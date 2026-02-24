import 'package:flutter/material.dart';

import '../../core/responsive.dart';

/// 统一背景：可选背景图（半透明叠底），否则纯 [surface]。
class AppBackground extends StatelessWidget {
  const AppBackground({
    super.key,
    this.isRoot = false,
    this.backgroundImage,
    this.showBackgroundImage = false,
    required this.child,
  });

  final bool isRoot;
  final ImageProvider? backgroundImage;
  final bool showBackgroundImage;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final useImage = showBackgroundImage &&
        backgroundImage != null &&
        (isRoot || isWideScreen(context));
    if (useImage) {
      return Container(
        decoration: BoxDecoration(
          color: surface,
          image: DecorationImage(
            image: backgroundImage!,
            fit: BoxFit.cover,
            opacity: 0.2,
            colorFilter: const ColorFilter.mode(
              Colors.black,
              BlendMode.darken,
            ),
          ),
        ),
        child: child,
      );
    }
    return Material(color: surface, child: child);
  }
}
