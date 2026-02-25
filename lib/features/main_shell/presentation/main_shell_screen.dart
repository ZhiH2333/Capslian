import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/responsive.dart';
import '../../../core/router/app_router.dart';
import '../../auth/data/models/user_model.dart';
import '../../auth/providers/auth_providers.dart';
import '../../../chat/presentation/chat_rooms_list_screen.dart';
import '../../posts/presentation/home_screen.dart';
import '../../profile/presentation/profile_screen.dart';

/// 主壳：窄屏底部 NavigationBar，宽屏（≥768）左侧 NavigationRail；「浏览、聊天、个人」。
class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  int _currentIndex = 0;

  static const List<_NavItem> _navItems = <_NavItem>[
    _NavItem(label: '浏览', icon: Icons.explore_outlined, selectedIcon: Icons.explore),
    _NavItem(label: '聊天', icon: Icons.chat_bubble_outline, selectedIcon: Icons.chat_bubble),
    _NavItem(label: '个人', icon: Icons.person_outline, selectedIcon: Icons.person),
  ];

  void _onDestinationSelected(int index, UserModel? user) {
    if (index == 1 || index == 2) {
      if (user == null) {
        context.go(AppRoutes.login);
        return;
      }
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final width = screenWidth(context);
    final useRail = useNavigationRail(width);
    return authState.when(
      data: (user) {
        final body = IndexedStack(
          index: _currentIndex,
          children: const <Widget>[
            HomeScreen(inShell: true),
            ChatRoomsListScreen(),
            ProfileScreen(inShell: true),
          ],
        );
        if (useRail) {
          final colorScheme = Theme.of(context).colorScheme;
          final padding = MediaQuery.viewPaddingOf(context);
          final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux;
          final topPadding = padding.top > 0 ? padding.top : (isDesktop ? 28.0 : 0.0);
          return Container(
            color: colorScheme.surfaceContainer,
            child: Padding(
              padding: EdgeInsets.only(
                top: topPadding,
                left: padding.left,
                right: padding.right,
                bottom: padding.bottom,
              ),
              child: Row(
                children: <Widget>[
                  NavigationRail(
                    backgroundColor: Colors.transparent,
                    selectedIndex: _currentIndex,
                    onDestinationSelected: (int index) => _onDestinationSelected(index, user),
                    labelType: NavigationRailLabelType.all,
                    destinations: _navItems
                        .map(
                          (_NavItem item) => NavigationRailDestination(
                            icon: Icon(item.icon),
                            selectedIcon: Icon(item.selectedIcon),
                            label: Text(item.label),
                          ),
                        )
                        .toList(),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(16)),
                      child: body,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: body,
          ),
          bottomNavigationBar: _ConditionalBottomNav(
            currentIndex: _currentIndex,
            onDestinationSelected: (int index) => _onDestinationSelected(index, user),
            navItems: _navItems,
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('加载失败'),
              TextButton(
                onPressed: () => context.push(AppRoutes.login),
                child: const Text('去登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.label, required this.icon, required this.selectedIcon});
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// 窄屏底部导航：毛玻璃、圆角、透明底、弱阴影。
class _ConditionalBottomNav extends StatelessWidget {
  const _ConditionalBottomNav({
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.navItems,
  });

  final int currentIndex;
  final void Function(int index) onDestinationSelected;
  final List<_NavItem> navItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ClipRRect(
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.8),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: NavigationBar(
              height: LayoutConstants.kBottomNavHeight,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              backgroundColor: Colors.transparent,
              indicatorColor: colorScheme.primary.withOpacity(0.2),
              selectedIndex: currentIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: navItems
                  .map(
                    (_NavItem item) => NavigationDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: item.label,
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}
