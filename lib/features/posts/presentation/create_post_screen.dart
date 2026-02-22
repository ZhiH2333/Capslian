import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../providers/posts_providers.dart';

/// 发布帖子：正文 + 可选图片（先上传再发布）。
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  final List<String> _imageUrls = [];
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (xFile == null || !mounted) return;
    setState(() => _error = null);
    try {
      final repo = ref.read(postsRepositoryProvider);
      final url = await repo.uploadImage(xFile.path, mimeType: xFile.mimeType ?? 'image/jpeg');
      setState(() => _imageUrls.add(url));
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final repo = ref.read(postsRepositoryProvider);
      await repo.createPost(
        content: _contentController.text.trim(),
        imageUrls: _imageUrls.isEmpty ? null : _imageUrls,
      );
      ref.invalidate(postsListProvider(const PostsListKey()));
      if (!mounted) return;
      context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发布')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            TextFormField(
              controller: _contentController,
              decoration: const InputDecoration(
                labelText: '内容',
                border: OutlineInputBorder(),
                hintText: '写点什么...',
                alignLabelWithHint: true,
              ),
              maxLines: 5,
              enabled: !_isLoading,
              validator: (String? v) {
                if ((v ?? '').trim().isEmpty) return '请输入内容';
                return null;
              },
            ),
            const SizedBox(height: 16),
            if (_imageUrls.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _imageUrls.map((url) {
                  return Stack(
                    children: <Widget>[
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: Image.network(url, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 20),
                          onPressed: () => setState(() => _imageUrls.remove(url)),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _pickImage,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('添加图片'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('发布'),
            ),
          ],
        ),
      ),
    );
  }
}
