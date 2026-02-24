import 'package:flutter/material.dart';

/// 文件列表占位，后续接入 /api/files 与 Presigned 上传。
class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文件')),
      body: const Center(child: Text('文件 · 敬请期待')),
    );
  }
}
