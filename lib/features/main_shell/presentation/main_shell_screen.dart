import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive.dart';
import '../../../core/router/app_router.dart';
import '../../auth/data/models/user_model.dart';
import '../../auth/providers/auth_providers.dart';
import '../../posts/presentation/home_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../direct/presentation/chat_tab_screen.dart';

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
          children: <Widget>[
            const HomeScreen(inShell: true),
            ChatTabScreen(
              onOpenChat: (String peerId, [String? peerDisplayName]) {
                final path = '${AppRoutes.direct}/$peerId';
                if (peerDisplayName != null && peerDisplayName.isNotEmpty) {
                  context.push('$path?peerName=${Uri.encodeComponent(peerDisplayName)}');
                } else {
                  context.push(path);
                }
              },
            ),
            const ProfileScreen(inShell: true),
          ],
        );
        if (useRail) {
          return Scaffold(
            body: Row(
              children: <Widget>[
                NavigationRail(
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
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (int index) => _onDestinationSelected(index, user),
            destinations: _navItems
                .map(
                  (_NavItem item) => NavigationDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: item.label,
                  ),
                )
                .toList(),
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
