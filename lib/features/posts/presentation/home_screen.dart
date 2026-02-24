import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/responsive.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../auth/data/models/user_model.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/posts_repository.dart';
import '../providers/posts_providers.dart';
import 'widgets/post_card.dart';

/// 首页：已登录显示时间线与发布 FAB，未登录显示登录/注册入口。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.inShell = false});

  /// 是否嵌入底部导航壳；为 true 时不显示顶部聊天/个人入口。
  final bool inShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final wide = isWideScreen(context);
    return AppScaffold(
      isNoBackground: wide,
      isWideScreen: wide,
      appBar: inShell
          ? null
          : AppBar(
              title: const Text('Molian'),
              actions: <Widget>[
                if (authState.valueOrNull != null) ...[
                  IconButton(
                    icon: const Icon(Icons.chat),
                    onPressed: () => context.push(AppRoutes.direct),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person),
                    onPressed: () => context.push(AppRoutes.profile),
                  ),
                ],
              ],
            ),
      body: authState.when(
        data: (UserModel? user) {
          if (user == null) {
            return _buildGuestBody(context);
          }
          return _TimelineBody();
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object err, StackTrace? stack) => EmptyState(
          title: '加载失败',
          description: err.toString(),
          action: TextButton(
            onPressed: () => context.push(AppRoutes.login),
            child: const Text('去登录'),
          ),
        ),
      ),
      floatingActionButton: authState.valueOrNull != null
          ? FloatingActionButton(
              onPressed: () => context.push(AppRoutes.createPost),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildGuestBody(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Text('首页（时间线占位）'),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => context.push(AppRoutes.login),
            child: const Text('登录'),
          ),
          TextButton(
            onPressed: () => context.push(AppRoutes.register),
            child: const Text('注册'),
          ),
        ],
      ),
    );
  }
}

class _TimelineBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(postsListProvider(const PostsListKey()));
    return pageAsync.when(
      data: (PostsPageResult result) {
        if (result.posts.isEmpty) {
          return EmptyState(
            title: '还没有帖子',
            description: '发一条动态吧',
            icon: Icons.edit_note,
            action: FilledButton.icon(
              onPressed: () => context.push(AppRoutes.createPost),
              icon: const Icon(Icons.add),
              label: const Text('发一条'),
            ),
          );
        }
        final bottomPadding = MediaQuery.paddingOf(context).bottom + 64;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(postsListProvider(const PostsListKey()));
          },
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: LayoutConstants.kContentMaxWidthWide),
              child: ListView.builder(
                padding: EdgeInsets.only(bottom: bottomPadding),
                itemCount: result.posts.length,
                itemBuilder: (BuildContext context, int index) {
                  return PostCard(post: result.posts[index]);
                },
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object err, StackTrace? stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('加载失败: ${err.toString()}'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(postsListProvider(const PostsListKey())),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

