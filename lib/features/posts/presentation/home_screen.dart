import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/responsive.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/image_lightbox.dart';
import '../../auth/data/models/user_model.dart';
import '../../auth/providers/auth_providers.dart';
import '../../files/data/files_repository.dart';
import '../../files/data/models/file_model.dart';
import '../../files/providers/files_providers.dart';
import '../../notifications/data/models/notification_model.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../notifications/providers/notifications_providers.dart';
import '../../realms/data/models/realm_model.dart';
import '../../realms/providers/realms_providers.dart';
import '../data/posts_repository.dart';
import '../providers/posts_providers.dart';
import 'widgets/post_card.dart';

/// 首页：已登录显示发现流与发布 FAB，未登录显示登录/注册入口。
/// 壳内时以 Tab 展示：发现、圈子、文件、通知（不跳转）。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.inShell = false});

  /// 是否嵌入底部导航壳；为 true 时以 Tab 展示发现/圈子/文件/通知。
  final bool inShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final wide = isWideScreen(context);
    return AppScaffold(
      isNoBackground: wide,
      isWideScreen: wide,
      appBar: inShell
          ? null
          : AppBar(
              title: const Text('Molian'),
              actions: <Widget>[
                if (authState.valueOrNull != null) ...[
                  IconButton(
                    icon: const Icon(Icons.chat),
                    onPressed: () => context.push(AppRoutes.chatRooms),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person),
                    onPressed: () => context.push(AppRoutes.profile),
                  ),
                ],
              ],
            ),
      body: authState.when(
        data: (UserModel? user) {
          if (user == null) {
            return _buildGuestBody(context);
          }
          if (inShell) {
            return DefaultTabController(
              length: 4,
              child: Column(
                children: <Widget>[
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: const <Widget>[
                      Tab(text: '发现'),
                      Tab(text: '圈子'),
                      Tab(text: '文件'),
                      Tab(text: '通知'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: <Widget>[
                        _FeedsTabContent(),
                        _RealmsTabContent(),
                        _FilesTabContent(),
                        _NotificationsTabContent(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return _FeedsTabContent();
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object err, StackTrace? stack) => EmptyState(
          title: '加载失败',
          description: err.toString(),
          action: TextButton(
            onPressed: () => context.push(AppRoutes.login),
            child: const Text('去登录'),
          ),
        ),
      ),
      floatingActionButton: authState.valueOrNull != null
          ? FloatingActionButton(
              onPressed: () => context.push(AppRoutes.createPost),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildGuestBody(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Text('首页（时间线占位）'),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => context.push(AppRoutes.login),
            child: const Text('登录'),
          ),
          TextButton(
            onPressed: () => context.push(AppRoutes.register),
            child: const Text('注册'),
          ),
        ],
      ),
    );
  }
}

class _FeedsTabContent extends ConsumerWidget {
  const _FeedsTabContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(feedsListProvider(const PostsListKey()));
    return pageAsync.when(
      data: (PostsPageResult result) {
        if (result.posts.isEmpty) {
          return EmptyState(
            title: '发现',
            description: '暂无推荐内容',
            icon: Icons.explore_outlined,
            action: FilledButton.icon(
              onPressed: () => context.push(AppRoutes.createPost),
              icon: const Icon(Icons.add),
              label: const Text('发一条'),
            ),
          );
        }
        final bottomPadding = MediaQuery.paddingOf(context).bottom + 64;
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(feedsListProvider(const PostsListKey())),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: LayoutConstants.kContentMaxWidthWide),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: EdgeInsets.only(bottom: bottomPadding),
                itemCount: result.posts.length,
                itemBuilder: (BuildContext context, int index) => PostCard(post: result.posts[index]),
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object err, StackTrace? st) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('加载失败: $err'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(feedsListProvider(const PostsListKey())),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RealmsTabContent extends ConsumerWidget {
  const _RealmsTabContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(realmsListProvider);
    return async.when(
      data: (List<RealmModel> realms) {
        if (realms.isEmpty) {
          return const EmptyState(
            title: '暂无圈子',
            description: '圈子功能即将开放',
            icon: Icons.people_outline,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(realmsListProvider),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: LayoutConstants.kSpacingXLarge),
            itemCount: realms.length,
            itemBuilder: (BuildContext context, int index) {
              final realm = realms[index];
              return ListTile(
                minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
                contentPadding: LayoutConstants.kListTileContentPadding,
                leading: CircleAvatar(
                  backgroundImage: realm.avatarUrl != null && realm.avatarUrl!.isNotEmpty
                      ? CachedNetworkImageProvider(realm.avatarUrl!)
                      : null,
                  child: realm.avatarUrl == null || realm.avatarUrl!.isEmpty
                      ? Text(realm.name.isNotEmpty ? realm.name[0] : '?')
                      : null,
                ),
                title: Text(realm.name),
                subtitle: realm.description != null && realm.description!.isNotEmpty
                    ? Text(realm.description!, maxLines: 2, overflow: TextOverflow.ellipsis)
                    : null,
                onTap: () => context.push(AppRoutes.realmDetail(realm.id), extra: realm),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object err, StackTrace? st) => EmptyState(
        title: '加载失败',
        description: err.toString(),
        action: TextButton(
          onPressed: () => ref.invalidate(realmsListProvider),
          child: const Text('重试'),
        ),
      ),
    );
  }
}

class _FilesTabContent extends ConsumerStatefulWidget {
  const _FilesTabContent();

  @override
  ConsumerState<_FilesTabContent> createState() => _FilesTabContentState();
}

class _FilesTabContentState extends ConsumerState<_FilesTabContent> {
  bool _isUploading = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null || !mounted) return;
    setState(() => _isUploading = true);
    try {
      final bytes = await xFile.readAsBytes();
      final repo = ref.read(filesRepositoryProvider);
      await repo.uploadAndConfirm(
        bytes,
        filename: xFile.name.isNotEmpty ? xFile.name : 'image.jpg',
        mimeType: 'image/jpeg',
      );
      ref.invalidate(filesListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已上传并登记')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(filesListProvider);
    return async.when(
      data: (List<FileModel> files) {
        if (files.isEmpty) {
          return EmptyState(
            title: '暂无文件',
            description: '上传图片或文件后将显示在这里',
            icon: Icons.folder_outlined,
            action: FilledButton.icon(
              onPressed: _isUploading ? null : _pickAndUpload,
              icon: _isUploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file),
              label: const Text('上传'),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(filesListProvider),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: LayoutConstants.kSpacingXLarge),
            itemCount: files.length,
            itemBuilder: (BuildContext context, int index) {
              final file = files[index];
              return _HomeFileTile(file: file);
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object err, StackTrace? st) => EmptyState(
        title: '加载失败',
        description: err.toString(),
        action: TextButton(
          onPressed: () => ref.invalidate(filesListProvider),
          child: const Text('重试'),
        ),
      ),
    );
  }
}

class _HomeFileTile extends StatelessWidget {
  const _HomeFileTile({required this.file});

  final FileModel file;

  @override
  Widget build(BuildContext context) {
    final url = FilesRepository.getAssetUrl(file.key);
    final isImage = file.mimeType != null && file.mimeType!.startsWith('image/');
    return ListTile(
      minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
      contentPadding: LayoutConstants.kListTileContentPadding,
      leading: isImage
          ? Image.network(url, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.insert_drive_file))
          : const Icon(Icons.insert_drive_file),
      title: Text(file.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(_formatSize(file.size)),
      onTap: () {
        if (isImage) {
          showImageLightbox(
            context,
            imageUrls: <String>[url],
            initialIndex: 0,
            heroTagPrefix: 'file-${file.id}',
          );
        }
      },
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _NotificationsTabContent extends ConsumerWidget {
  const _NotificationsTabContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsListProvider(const NotificationsListKey()));
    return async.when(
      data: (NotificationsPageResult result) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    final repo = ref.read(notificationsRepositoryProvider);
                    await repo.markRead();
                    ref.invalidate(notificationsListProvider(const NotificationsListKey()));
                  },
                  child: const Text('全部已读'),
                ),
              ),
            ),
            Expanded(
              child: result.notifications.isEmpty
                  ? const EmptyState(
                      title: '暂无通知',
                      description: '新的点赞、评论、关注等会出现在这里',
                      icon: Icons.notifications_none_outlined,
                    )
                  : RefreshIndicator(
                      onRefresh: () async => ref.invalidate(notificationsListProvider(const NotificationsListKey())),
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: LayoutConstants.kSpacingXLarge),
                        itemCount: result.notifications.length,
                        itemBuilder: (BuildContext context, int index) {
                          final n = result.notifications[index];
                          return _HomeNotificationTile(
                            notification: n,
                            onMarkRead: () async {
                              final repo = ref.read(notificationsRepositoryProvider);
                              await repo.markRead(id: n.id);
                              ref.invalidate(notificationsListProvider(const NotificationsListKey()));
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object err, StackTrace? st) => EmptyState(
        title: '加载失败',
        description: err.toString(),
        action: TextButton(
          onPressed: () => ref.invalidate(notificationsListProvider(const NotificationsListKey())),
          child: const Text('重试'),
        ),
      ),
    );
  }
}

class _HomeNotificationTile extends StatelessWidget {
  const _HomeNotificationTile({required this.notification, required this.onMarkRead});

  final NotificationModel notification;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = !notification.read;
    return ListTile(
      minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
      contentPadding: LayoutConstants.kListTileContentPadding,
      leading: CircleAvatar(
        backgroundColor: isUnread ? theme.colorScheme.primaryContainer : null,
        child: Icon(
          _iconForType(notification.type),
          color: isUnread ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.outline,
        ),
      ),
      title: Text(
        notification.title ?? notification.type,
        style: TextStyle(fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal),
      ),
      subtitle: notification.body != null && notification.body!.isNotEmpty
          ? Text(notification.body!, maxLines: 2, overflow: TextOverflow.ellipsis)
          : null,
      trailing: isUnread ? TextButton(onPressed: onMarkRead, child: const Text('标为已读')) : null,
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite_outline;
      case 'comment':
        return Icons.chat_bubble_outline;
      case 'follow':
        return Icons.person_add_outlined;
      case 'friend_request':
        return Icons.mail_outline;
      default:
        return Icons.notifications_outlined;
    }
  }
}
