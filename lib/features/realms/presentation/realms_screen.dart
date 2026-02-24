import 'package:flutter/material.dart';

/// 圈子列表占位，后续接入 /api/realms。
class RealmsScreen extends StatelessWidget {
  const RealmsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('圈子')),
      body: const Center(child: Text('圈子 · 敬请期待')),
    );
  }
}
