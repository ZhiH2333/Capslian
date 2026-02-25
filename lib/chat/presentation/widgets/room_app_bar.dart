import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/chat_room_model.dart';
import '../../pods/chat_subscribe.dart';

/// 聊天房间顶部 AppBar，显示房间名称、成员数与输入状态。
class RoomAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const RoomAppBar({
    super.key,
    required this.room,
    this.actions,
  });

  final ChatRoom room;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typingUsers = ref.watch(typingUsersProvider(room.id));
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            room.name,
            style: Theme.of(context).textTheme.titleMedium,
            overflow: TextOverflow.ellipsis,
          ),
          if (typingUsers.isNotEmpty)
            Text(
              '正在输入...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            )
          else if (room.memberCount > 0)
            Text(
              '${room.memberCount} 位成员',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
        ],
      ),
      centerTitle: true,
      actions: actions,
    );
  }
}
