import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../../auth/data/models/user_model.dart';
import '../../auth/providers/auth_providers.dart';
import '../../posts/providers/posts_providers.dart';
import '../providers/profile_providers.dart';

/// 个人资料：展示与编辑 display_name、bio、头像；登出。
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _initialized = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _initFromUser(UserModel user) {
    if (_initialized) return;
    _initialized = true;
    _displayNameController.text = user.displayName ?? user.username;
    _bioController.text = user.bio ?? '';
  }

  Future<void> _pickAvatar() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (xFile == null || !mounted) return;
    setState(() {
      _error = null;
      _isLoading = true;
    });
    try {
      final postsRepo = ref.read(postsRepositoryProvider);
      final url = await postsRepo.uploadImage(xFile.path, mimeType: xFile.mimeType ?? 'image/jpeg');
      final profileRepo = ref.read(profileRepositoryProvider);
      await profileRepo.updateMe(avatarUrl: url);
      ref.invalidate(authStateProvider);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profileRepo = ref.read(profileRepositoryProvider);
      await profileRepo.updateMe(
        displayName: _displayNameController.text.trim(),
        bio: _bioController.text.trim(),
      );
      ref.invalidate(authStateProvider);
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    return authState.when(
      data: (UserModel? user) {
        if (user == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('个人资料')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Text('请先登录'),
                  TextButton(onPressed: () => context.go(AppRoutes.login), child: const Text('去登录')),
                ],
              ),
            ),
          );
        }
        _initFromUser(user);
        return Scaffold(
          appBar: AppBar(
            title: const Text('个人资料'),
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => context.push(AppRoutes.settings),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  await ref.read(authStateProvider.notifier).logout();
                  if (context.mounted) context.go(AppRoutes.home);
                },
              ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: <Widget>[
                Center(
                  child: GestureDetector(
                    onTap: _isLoading ? null : _pickAvatar,
                    child: Stack(
                      children: <Widget>[
                        CircleAvatar(
                          radius: 48,
                          backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                              ? NetworkImage(user.avatarUrl!)
                              : null,
                          child: user.avatarUrl == null || user.avatarUrl!.isEmpty
                              ? Text((user.displayName ?? user.username).isNotEmpty ? (user.displayName ?? user.username)[0] : '?')
                              : null,
                        ),
                        if (_isLoading)
                          const Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: Colors.black26),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(child: Text(_isLoading ? '上传中...' : '点击头像更换')),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(labelText: '显示名', border: OutlineInputBorder()),
                  enabled: !_isLoading,
                  validator: (String? v) => (v?.trim() ?? '').isEmpty ? '请输入显示名' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _bioController,
                  decoration: const InputDecoration(labelText: '简介', border: OutlineInputBorder(), alignLabelWithHint: true),
                  maxLines: 3,
                  enabled: !_isLoading,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isLoading ? null : _save,
                  child: _isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('保存'),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => Scaffold(appBar: AppBar(title: const Text('个人资料')), body: const Center(child: CircularProgressIndicator())),
      error: (Object err, StackTrace? stack) => Scaffold(
        appBar: AppBar(title: const Text('个人资料')),
        body: Center(child: TextButton(onPressed: () => context.go(AppRoutes.login), child: const Text('去登录'))),
      ),
    );
  }
}
