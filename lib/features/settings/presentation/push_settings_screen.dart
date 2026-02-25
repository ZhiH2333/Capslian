import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';

/// 推送通知说明：登录后 FCM token 已自动上报，可在此查看说明。
class PushSettingsScreen extends StatelessWidget {
  const PushSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: const Text('推送通知'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(LayoutConstants.kSpacingXLarge),
        children: <Widget>[
          const Text(
            '推送说明',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: LayoutConstants.kSpacingSmall),
          Text(
            '登录成功后，本应用会将设备推送 token 上报至服务器，用于接收点赞、评论、关注、私信等通知。'
            '若需关闭推送，请在系统设置中管理本应用的通知权限。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: LayoutConstants.kSpacingXLarge),
          ListTile(
            minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('通知中心'),
            subtitle: const Text('查看已收到的通知'),
            onTap: () => context.push(AppRoutes.notifications),
          ),
        ],
      ),
    );
  }
}
