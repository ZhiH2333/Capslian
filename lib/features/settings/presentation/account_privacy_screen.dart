import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../../auth/providers/auth_providers.dart';

/// 账号与隐私：编辑资料入口、登出等。
class AccountPrivacyScreen extends ConsumerWidget {
  const AccountPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: const Text('账号与隐私'),
      ),
      body: ListView(
        children: <Widget>[
          ListTile(
            minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
            contentPadding: LayoutConstants.kListTileContentPadding,
            leading: const Icon(Icons.person_outline),
            title: const Text('编辑个人资料'),
            subtitle: const Text('修改显示名、简介、头像'),
            onTap: () => context.push(AppRoutes.profile),
          ),
          const Divider(),
          ListTile(
            minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
            contentPadding: LayoutConstants.kListTileContentPadding,
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text('退出登录', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () async {
              await ref.read(authStateProvider.notifier).logout();
              if (context.mounted) context.go(AppRoutes.home);
            },
          ),
        ],
      ),
    );
  }
}
