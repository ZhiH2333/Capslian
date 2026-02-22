import 'package:flutter/material.dart';

/// 关注/粉丝等占位（V1 实现时补全）。
class SocialScreen extends StatelessWidget {
  const SocialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关注')),
      body: const Center(child: Text('关注列表（占位）')),
    );
  }
}
