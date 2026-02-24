import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../providers/auth_providers.dart';

/// 登录页：用户名、密码、提交后更新 authState 并跳转首页。
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(authStateProvider.notifier).login(
          _usernameController.text.trim(),
          _passwordController.text,
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
        title: const Text('登录'),
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
                hintText: '请输入用户名',
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
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: '密码',
                border: const OutlineInputBorder(),
                hintText: '请输入密码',
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
              child: isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('登录'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: isLoading ? null : () => context.go(AppRoutes.register),
              child: const Text('没有账号？去注册'),
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

