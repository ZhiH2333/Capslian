import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart' as resp;
import 'app_background.dart';

/// 统一页面壳：透明 Scaffold、可延伸 body、可选背景；Escape 退栈。
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.isNoBackground = false,
    this.isWideScreen,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;

  /// 为 true 或宽屏时不包一层 [AppBackground]。
  final bool isNoBackground;

  /// 未传时根据 [context] 用 [isWideScreen] 判断。
  final bool? isWideScreen;

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen ?? resp.isWideScreen(context);
    final useBackground = !isNoBackground && !wide;
    final appBarHeight = appBar != null ? appBar!.preferredSize.height : 0.0;
    final topPadding = MediaQuery.paddingOf(context).top;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color scaffoldBg = (useBackground || appBar != null)
        ? colorScheme.surface
        : Colors.transparent;
    final Widget bodyContent = useBackground
        ? ColoredBox(
            color: colorScheme.surface,
            child: body,
          )
        : body;
    final scaffold = Scaffold(
      backgroundColor: scaffoldBg,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: appBar,
      body: Focus(
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape &&
              Navigator.of(context).canPop()) {
            context.pop();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          children: <Widget>[
            SizedBox(height: appBarHeight + topPadding),
            Expanded(child: bodyContent),
          ],
        ),
      ),
      floatingActionButton: floatingActionButton,
    );
    if (useBackground) {
      return AppBackground(isRoot: true, child: scaffold);
    }
    return scaffold;
  }
}
