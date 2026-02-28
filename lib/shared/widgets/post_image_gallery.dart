import 'package:flutter/material.dart';

/// 滑动图片画廊：主图居中，左右各露出一部分上一张/下一张以提示可滑动，
/// 非当前项缩放 0.93，底部左侧显示「当前/总数」，圆角 12，300ms 缩放动画。
///
/// 必选 [imageUrls]；可选 [height] 未传时默认 240（建议范围 220～260）。
/// 可选 [onImageTap] 用于点击当前页（如打开灯箱）。
class PostImageGallery extends StatefulWidget {
  const PostImageGallery({
    super.key,
    required this.imageUrls,
    this.height,
    this.onImageTap,
  });

  final List<String> imageUrls;
  final double? height;
  final void Function(int index)? onImageTap;

  @override
  State<PostImageGallery> createState() => _PostImageGalleryState();
}

class _PostImageGalleryState extends State<PostImageGallery> {
  static const double _defaultHeight = 240;
  /// 每页占 84% 宽，左右各约 8% 露出上一张/下一张。
  static const double _viewportFraction = 0.84;
  static const double _inactiveScale = 0.93;
  static const double _borderRadius = 12;
  static const Duration _scaleDuration = Duration(milliseconds: 300);

  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: _viewportFraction);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  double get _height => widget.height ?? _defaultHeight;

  @override
  Widget build(BuildContext context) {
    final List<String> urls = widget.imageUrls;
    if (urls.isEmpty) {
      return SizedBox(height: _height);
    }
    final int total = urls.length;
    return SizedBox(
      height: _height,
      child: Stack(
        children: <Widget>[
          PageView.builder(
            controller: _pageController,
            onPageChanged: (int index) {
              setState(() => _currentIndex = index);
            },
            itemCount: total,
            itemBuilder: (BuildContext context, int index) {
              final bool isActive = index == _currentIndex;
              return GestureDetector(
                onTap: widget.onImageTap != null
                    ? () => widget.onImageTap!(index)
                    : null,
                child: AnimatedScale(
                  scale: isActive ? 1.0 : _inactiveScale,
                  duration: _scaleDuration,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(_borderRadius),
                      child: Image.network(
                        urls[index],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) =>
                            _buildPlaceholder(context),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 12,
            bottom: 10,
            child: _PageIndicator(current: _currentIndex + 1, total: total),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Icon(
        Icons.broken_image_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 底部左侧页码指示器，显示「当前/总数」。
class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$current/$total',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ========== 用法示例 ==========
// PostImageGallery(
//   imageUrls: ['https://example.com/1.jpg', 'https://example.com/2.jpg'],
//   height: 240,
//   onImageTap: (int index) => showImageLightbox(context, imageUrls: imageUrls, initialIndex: index, heroTagPrefix: 'post_img'),
// )
