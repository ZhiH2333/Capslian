import 'package:flutter/material.dart';

/// 断点宽度（逻辑像素）：窄屏 / 中屏 / 宽屏。
const double breakpointTablet = 768;
const double breakpointDesktop = 1024;
const double breakpointWide = 1280;

/// 根据 [width] 判断是否为窄屏（手机），否则为平板或桌面。
bool isNarrowScreen(double width) => width < breakpointTablet;

/// 根据 [width] 判断是否使用左侧 NavigationRail（≥768）。
bool useNavigationRail(double width) => width >= breakpointTablet;

/// 根据 [width] 判断是否使用侧栏详情布局（≥1024）。
bool useSidebarLayout(double width) => width >= breakpointDesktop;

/// 当前上下文宽度（MediaQuery）。
double screenWidth(BuildContext context) => MediaQuery.sizeOf(context).width;
