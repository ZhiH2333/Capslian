import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/responsive.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../posts/data/posts_repository.dart';
import '../../posts/presentation/widgets/post_card.dart';
import '../../posts/providers/posts_providers.dart';

/// 发现页：展示探索流（/api/feeds），与首页时间线类似。
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = isWideScreen(context);
    return AppScaffold(
      isNoBackground: wide,
      isWideScreen: wide,
      appBar: AppBar(title: const Text('发现')),
      body: Consumer(
        builder: (BuildContext context, WidgetRef ref, _) {
          final pageAsync = ref.watch(feedsListProvider(const PostsListKey()));
          return pageAsync.when(
            data: (PostsPageResult result) {
              if (result.posts.isEmpty) {
                return EmptyState(
                  title: '发现',
                  description: '暂无推荐内容',
                  icon: Icons.explore_outlined,
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
                  ref.invalidate(feedsListProvider(const PostsListKey()));
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
            error: (Object err, StackTrace? st) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text('加载失败: ${err.toString()}'),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.invalidate(feedsListProvider(const PostsListKey())),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(AppRoutes.createPost),
        child: const Icon(Icons.add),
      ),
    );
  }
}
