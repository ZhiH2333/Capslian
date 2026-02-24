import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../providers/auth_providers.dart';

/// 注册页：用户名、密码、显示名（可选），提交后更新 authState 并跳转首页。
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(authStateProvider.notifier).register(
          _usernameController.text.trim(),
          _passwordController.text,
          displayName: _displayNameController.text.trim().isEmpty ? null : _displayNameController.text.trim(),
        );
    if (!mounted) return;
    final state = ref.read(authStateProvider);
    if (state.hasValue && state.value != null) context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading;
    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: const Text('注册'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            const SizedBox(height: 24),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
                hintText: '至少 2 个字符',
              ),
              textInputAction: TextInputAction.next,
              enabled: !isLoading,
              validator: (String? v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return '请输入用户名';
                if (t.length < 2) return '用户名至少 2 个字符';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _displayNameController,
              decoration: const InputDecoration(
                labelText: '显示名（可选）',
                border: OutlineInputBorder(),
                hintText: '用于展示的名称',
              ),
              textInputAction: TextInputAction.next,
              enabled: !isLoading,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: '密码',
                border: const OutlineInputBorder(),
                hintText: '至少 6 个字符',
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              enabled: !isLoading,
              onFieldSubmitted: (_) => _submit(),
              validator: (String? v) {
                if ((v ?? '').isEmpty) return '请输入密码';
                if ((v ?? '').length < 6) return '密码至少 6 个字符';
                return null;
              },
            ),
            if (authState.hasError) ...[
              const SizedBox(height: 12),
              Text(
                authState.error.toString().replaceFirst('Exception: ', ''),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: isLoading ? null : _submit,
              child: isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('注册'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: isLoading ? null : () => context.go(AppRoutes.login),
              child: const Text('已有账号？去登录'),
            ),
            TextButton(
              onPressed: isLoading ? null : () => context.go(AppRoutes.home),
              child: const Text('返回首页'),
            ),
          ],
        ),
      ),
    );
  }
}
