import 'package:flutter/material.dart';

import '../../../core/responsive.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../../../shared/widgets/empty_state.dart';

/// 文件列表占位，后续接入 /api/files 与 Presigned 上传。
class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    return AppScaffold(
      isNoBackground: wide,
      isWideScreen: wide,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: TextField(
            decoration: InputDecoration(
              hintText: '搜索文件',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 14),
            readOnly: true,
            onTap: () {},
          ),
        ),
        actions: const <Widget>[
          IconButton(icon: Icon(Icons.delete_outline), onPressed: null),
          IconButton(icon: Icon(Icons.folder_outlined), onPressed: null),
          SizedBox(width: 8),
        ],
      ),
      body: const EmptyState(
        title: '文件',
        description: '敬请期待：文件列表与上传',
        icon: Icons.folder_outlined,
      ),
    );
  }
}
