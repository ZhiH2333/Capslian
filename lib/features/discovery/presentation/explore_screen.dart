import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';

/// 发现/探索页占位，后续接入 Feed、文章、直播等。
class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    return AppScaffold(
      isNoBackground: wide,
      isWideScreen: wide,
      appBar: AppBar(title: const Text('发现')),
      body: const EmptyState(
        title: '发现',
        description: '敬请期待：Feed、文章、直播等',
        icon: Icons.explore_outlined,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(AppRoutes.createPost),
        child: const Icon(Icons.add),
      ),
    );
  }
}
