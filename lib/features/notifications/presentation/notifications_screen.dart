import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/responsive.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/models/notification_model.dart';
import '../data/notifications_repository.dart';
import '../providers/notifications_providers.dart';

/// 通知中心：列表展示、标记已读。
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = isWideScreen(context);
    return AppScaffold(
      isNoBackground: wide,
      isWideScreen: wide,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: const Text('通知'),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              final repo = ref.read(notificationsRepositoryProvider);
              await repo.markRead();
              ref.invalidate(notificationsListProvider(const NotificationsListKey()));
            },
            child: const Text('全部已读'),
          ),
        ],
      ),
      body: Consumer(
        builder: (BuildContext context, WidgetRef ref, _) {
          final async = ref.watch(notificationsListProvider(const NotificationsListKey()));
          return async.when(
            data: (NotificationsPageResult result) {
              if (result.notifications.isEmpty) {
                return const EmptyState(
                  title: '暂无通知',
                  description: '新的点赞、评论、关注等会出现在这里',
                  icon: Icons.notifications_none_outlined,
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(notificationsListProvider(const NotificationsListKey()));
                },
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: LayoutConstants.kSpacingXLarge),
                  itemCount: result.notifications.length,
                  itemBuilder: (BuildContext context, int index) {
                    return _NotificationTile(
                      notification: result.notifications[index],
                      onMarkRead: () async {
                        final repo = ref.read(notificationsRepositoryProvider);
                        await repo.markRead(id: result.notifications[index].id);
                        ref.invalidate(notificationsListProvider(const NotificationsListKey()));
                      },
                    );
                  },
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object err, StackTrace? st) => EmptyState(
              title: '加载失败',
              description: err.toString(),
              action: TextButton(
                onPressed: () => ref.invalidate(notificationsListProvider(const NotificationsListKey())),
                child: const Text('重试'),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onMarkRead});

  final NotificationModel notification;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = !notification.read;
    return ListTile(
      minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
      contentPadding: LayoutConstants.kListTileContentPadding,
      leading: CircleAvatar(
        backgroundColor: isUnread ? theme.colorScheme.primaryContainer : null,
        child: Icon(
          _iconForType(notification.type),
          color: isUnread ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.outline,
        ),
      ),
      title: Text(
        notification.title ?? notification.type,
        style: TextStyle(
          fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: notification.body != null && notification.body!.isNotEmpty
          ? Text(notification.body!, maxLines: 2, overflow: TextOverflow.ellipsis)
          : null,
      trailing: isUnread
          ? TextButton(
              onPressed: onMarkRead,
              child: const Text('标为已读'),
            )
          : null,
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite_outline;
      case 'comment':
        return Icons.chat_bubble_outline;
      case 'follow':
        return Icons.person_add_outlined;
      case 'friend_request':
        return Icons.mail_outline;
      default:
        return Icons.notifications_outlined;
    }
  }
}
