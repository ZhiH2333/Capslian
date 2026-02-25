import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/responsive.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../data/models/realm_model.dart';
import '../data/realms_repository.dart';
import '../providers/realms_providers.dart';

/// 圈子详情：展示信息，加入/退出（乐观更新）。
class RealmDetailScreen extends ConsumerStatefulWidget {
  const RealmDetailScreen({super.key, required this.realmId, this.initialRealm});

  final String realmId;
  final RealmModel? initialRealm;

  @override
  ConsumerState<RealmDetailScreen> createState() => _RealmDetailScreenState();
}

class _RealmDetailScreenState extends ConsumerState<RealmDetailScreen> {
  bool _joined = false;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    final async = ref.watch(realmDetailProvider(widget.realmId));
    final realm = async.valueOrNull ?? widget.initialRealm;
    return AppScaffold(
      isNoBackground: wide,
      isWideScreen: wide,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text(realm?.name ?? '圈子'),
      ),
      body: realm == null
          ? async.when(
              data: (_) => const Center(child: Text('圈子不存在')),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, _) => Center(child: Text('加载失败: $e')),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(LayoutConstants.kSpacingXLarge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: CircleAvatar(
                      radius: 48,
                      backgroundImage: realm.avatarUrl != null && realm.avatarUrl!.isNotEmpty
                          ? CachedNetworkImageProvider(realm.avatarUrl!)
                          : null,
                      child: realm.avatarUrl == null || realm.avatarUrl!.isEmpty
                          ? Text(realm.name.isNotEmpty ? realm.name[0] : '?', style: const TextStyle(fontSize: 36))
                          : null,
                    ),
                  ),
                  const SizedBox(height: LayoutConstants.kSpacingLarge),
                  Text(
                    realm.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  if (realm.slug.isNotEmpty) ...[
                    const SizedBox(height: LayoutConstants.kSpacingSmall),
                    Text(
                      '@${realm.slug}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (realm.description != null && realm.description!.isNotEmpty) ...[
                    const SizedBox(height: LayoutConstants.kSpacingLarge),
                    Text(realm.description!, style: Theme.of(context).textTheme.bodyLarge),
                  ],
                  const SizedBox(height: LayoutConstants.kSpacingXLarge),
                  FilledButton(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            setState(() => _isLoading = true);
                            try {
                              final repo = ref.read(realmsRepositoryProvider);
                              if (_joined) {
                                await repo.leaveRealm(widget.realmId);
                                if (mounted) setState(() => _joined = false);
                              } else {
                                await repo.joinRealm(widget.realmId);
                                if (mounted) setState(() => _joined = true);
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('操作失败: $e')),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _isLoading = false);
                            }
                          },
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_joined ? '退出圈子' : '加入圈子'),
                  ),
                ],
              ),
            ),
    );
  }
}
