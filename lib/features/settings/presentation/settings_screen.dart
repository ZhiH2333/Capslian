import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_mode_provider.dart';

/// 设置页：深色模式切换；个人中心/推送等占位。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: <Widget>[
          ListTile(
            title: const Text('深色模式'),
            subtitle: Text(themeMode == ThemeMode.dark ? '深色' : themeMode == ThemeMode.light ? '浅色' : '跟随系统'),
            trailing: DropdownButton<ThemeMode>(
              value: themeMode,
              items: const <DropdownMenuItem<ThemeMode>>[
                DropdownMenuItem<ThemeMode>(value: ThemeMode.light, child: Text('浅色')),
                DropdownMenuItem<ThemeMode>(value: ThemeMode.dark, child: Text('深色')),
                DropdownMenuItem<ThemeMode>(value: ThemeMode.system, child: Text('系统')),
              ],
              onChanged: (ThemeMode? value) {
                if (value != null) ref.read(themeModeProvider.notifier).setThemeMode(value);
              },
            ),
          ),
          const Divider(),
          const ListTile(title: Text('账号与隐私'), subtitle: Text('（占位）')),
          const ListTile(title: Text('推送通知'), subtitle: Text('（占位，可选接入 APNs/FCM）')),
        ],
      ),
    );
  }
}
