import 'package:flutter/material.dart';

import '../../core/responsive.dart';

/// 宽屏时主区 + 侧栏详情，窄屏时仅显示主区（详情通过导航全屏）。
class ResponsiveSidebar extends StatelessWidget {
  const ResponsiveSidebar({
    super.key,
    required this.list,
    this.detail,
    this.sidebarWidth = 360,
  });

  final Widget list;
  final Widget? detail;
  final double sidebarWidth;

  @override
  Widget build(BuildContext context) {
    final width = screenWidth(context);
    if (useSidebarLayout(width) && detail != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: list),
          SizedBox(
            width: sidebarWidth,
            child: Material(
              elevation: 0,
              child: detail!,
            ),
          ),
        ],
      );
    }
    return list;
  }
}
