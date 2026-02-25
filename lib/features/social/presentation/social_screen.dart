import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/responsive.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../providers/social_providers.dart';

/// 关注/粉丝列表：Tab 切换，关注列表可取消关注。
class SocialScreen extends ConsumerWidget {
  const SocialScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = isWideScreen(context);
    return DefaultTabController(
      length: 2,
      child: AppScaffold(
        isNoBackground: wide,
        isWideScreen: wide,
        appBar: AppBar(
          leading: const AutoLeadingButton(),
          title: const Text('关注与粉丝'),
          bottom: const TabBar(
            tabs: <Tab>[
              Tab(text: '关注'),
              Tab(text: '粉丝'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            _FollowingList(),
            _FollowersList(),
          ],
        ),
      ),
    );
  }
}

class _FollowingList extends ConsumerWidget {
  const _FollowingList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(followingListProvider);
    return async.when(
      data: (List<Map<String, dynamic>> users) {
        if (users.isEmpty) {
          return const EmptyState(
            title: '暂无关注',
            description: '你关注的人会出现在这里',
            icon: Icons.person_add_outlined,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(followingListProvider),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: LayoutConstants.kSpacingXLarge),
            itemCount: users.length,
            itemBuilder: (BuildContext context, int index) {
              final u = users[index];
              final id = u['id'] as String? ?? '';
              final name = u['display_name'] as String? ?? u['username'] as String? ?? '未知';
              final handle = u['username'] as String? ?? '';
              final avatarUrl = u['avatar_url'] as String?;
              return ListTile(
                minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
                contentPadding: LayoutConstants.kListTileContentPadding,
                leading: CircleAvatar(
                  backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl == null || avatarUrl.isEmpty ? Text(name.isNotEmpty ? name[0] : '?') : null,
                ),
                title: Text(name),
                subtitle: handle.isNotEmpty ? Text('@$handle') : null,
                trailing: TextButton(
                  onPressed: () async {
                    try {
                      await ref.read(socialRepositoryProvider).unfollow(id);
                      ref.invalidate(followingListProvider);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('取关失败: $e')));
                      }
                    }
                  },
                  child: const Text('取消关注'),
                ),
                onTap: () => context.push('${AppRoutes.directConversation(id)}?peerName=${Uri.encodeQueryComponent(name)}'),
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
          onPressed: () => ref.invalidate(followingListProvider),
          child: const Text('重试'),
        ),
      ),
    );
  }
}

class _FollowersList extends ConsumerWidget {
  const _FollowersList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(followersListProvider);
    return async.when(
      data: (List<Map<String, dynamic>> users) {
        if (users.isEmpty) {
          return const EmptyState(
            title: '暂无粉丝',
            description: '关注你的人会出现在这里',
            icon: Icons.people_outline,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(followersListProvider),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: LayoutConstants.kSpacingXLarge),
            itemCount: users.length,
            itemBuilder: (BuildContext context, int index) {
              final u = users[index];
              final id = u['id'] as String? ?? '';
              final name = u['display_name'] as String? ?? u['username'] as String? ?? '未知';
              final handle = u['username'] as String? ?? '';
              final avatarUrl = u['avatar_url'] as String?;
              return ListTile(
                minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
                contentPadding: LayoutConstants.kListTileContentPadding,
                leading: CircleAvatar(
                  backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl == null || avatarUrl.isEmpty ? Text(name.isNotEmpty ? name[0] : '?') : null,
                ),
                title: Text(name),
                subtitle: handle.isNotEmpty ? Text('@$handle') : null,
                onTap: () => context.push('${AppRoutes.directConversation(id)}?peerName=${Uri.encodeQueryComponent(name)}'),
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
          onPressed: () => ref.invalidate(followersListProvider),
          child: const Text('重试'),
        ),
      ),
    );
  }
}
