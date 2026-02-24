import 'package:flutter/material.dart';

import '../../../core/responsive.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';

/// 圈子列表占位，后续接入 /api/realms。
class RealmsScreen extends StatelessWidget {
  const RealmsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    return AppScaffold(
      isNoBackground: wide,
      isWideScreen: wide,
      appBar: AppBar(
        title: const Text('圈子'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
          IconButton(
            icon: Badge(
              label: const Text('0'),
              child: const Icon(Icons.mail_outline),
            ),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: const EmptyState(
        title: '圈子',
        description: '敬请期待：加入或创建圈子',
        icon: Icons.people_outline,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}
