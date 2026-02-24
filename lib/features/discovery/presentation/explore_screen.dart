import 'package:flutter/material.dart';

/// 发现/探索页占位，后续接入 Feed、文章、直播等。
class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发现')),
      body: const Center(child: Text('发现 · 敬请期待')),
    );
  }
}
