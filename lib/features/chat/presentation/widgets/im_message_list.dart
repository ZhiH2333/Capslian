import 'package:flutter/material.dart';

import '../../data/models/sn_chat_message.dart';
import 'chat_bubble.dart';

/// 使用 CustomScrollView + center 实现双向插入不跳动的聊天列表（参见掘金文章）。
/// [aboveCenter] 为更旧的消息（向上滑动加载更多），[belowCenter] 为更新消息（新消息追加在此）。
/// [reverse] 为 true 时列表从底部开始，新消息在下方。
/// [onLoadMore] 当用户向上滑动接近顶部时触发加载更多。
/// [currentUserId] 用于区分己方/对方气泡。
class ImMessageList extends StatelessWidget {
  const ImMessageList({
    super.key,
    required this.aboveCenter,
    required this.belowCenter,
    required this.currentUserId,
    this.scrollController,
    this.reverse = true,
    this.padding,
    this.onLoadMore,
    this.loadingMore = false,
    this.itemBuilder,
  });

  final List<SnChatMessage> aboveCenter;
  final List<SnChatMessage> belowCenter;
  final String currentUserId;
  final ScrollController? scrollController;
  final bool reverse;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onLoadMore;
  final bool loadingMore;
  final Widget Function(BuildContext context, SnChatMessage message)? itemBuilder;

  static const Key _centerKey = ValueKey<String>('im_list_center');

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      reverse: reverse,
      center: _centerKey,
      slivers: <Widget>[
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
              final item = belowCenter[index];
              return itemBuilder != null
                  ? itemBuilder!(context, item)
                  : ChatBubble(message: item, isMe: item.senderId == currentUserId);
            },
            childCount: belowCenter.length,
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.zero,
          key: _centerKey,
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
              if (index == 0 && loadingMore) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final actualIndex = loadingMore ? index - 1 : index;
              if (actualIndex < 0) return const SizedBox.shrink();
              final item = aboveCenter[actualIndex];
              return itemBuilder != null
                  ? itemBuilder!(context, item)
                  : ChatBubble(message: item, isMe: item.senderId == currentUserId);
            },
            childCount: aboveCenter.length + (loadingMore ? 1 : 0),
          ),
        ),
        if (padding != null)
          SliverPadding(padding: padding!),
      ],
    );
  }
}
