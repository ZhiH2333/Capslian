import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// 全屏图片灯箱，支持多图切换、缩放/平移、Hero 动画、下滑关闭。
class ImageLightbox extends StatefulWidget {
  const ImageLightbox({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.heroTagPrefix = 'img',
  });

  final List<String> imageUrls;
  final int initialIndex;
  final String heroTagPrefix;

  @override
  State<ImageLightbox> createState() => _ImageLightboxState();
}

class _ImageLightboxState extends State<ImageLightbox> {
  late final PageController _pageController;
  late int _currentIndex;
  double _backgroundOpacity = 1.0;
  double _dragStartY = 0.0;
  double _dragOffsetY = 0.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _dragStartY = details.globalPosition.dy;
    _dragOffsetY = 0;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final double dy = details.globalPosition.dy - _dragStartY;
    if (dy < 0) return;
    final double screenHeight = MediaQuery.sizeOf(context).height;
    setState(() {
      _dragOffsetY = dy;
      _backgroundOpacity = (1.0 - dy / screenHeight * 2).clamp(0.0, 1.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    const double threshold = 120.0;
    final double velocity = details.primaryVelocity ?? 0;
    if (_dragOffsetY > threshold || velocity > 600) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _dragOffsetY = 0;
        _backgroundOpacity = 1.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasMultiple = widget.imageUrls.length > 1;
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: _backgroundOpacity),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: _backgroundOpacity * 0.6),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: hasMultiple
            ? Text(
                '${_currentIndex + 1} / ${widget.imageUrls.length}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              )
            : null,
        centerTitle: true,
      ),
      body: GestureDetector(
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Transform.translate(
          offset: Offset(0, _dragOffsetY),
          child: PhotoViewGallery.builder(
            pageController: _pageController,
            itemCount: widget.imageUrls.length,
            onPageChanged: (int index) => setState(() => _currentIndex = index),
            builder: (BuildContext ctx, int index) {
              return PhotoViewGalleryPageOptions(
                imageProvider: CachedNetworkImageProvider(widget.imageUrls[index]),
                heroAttributes: PhotoViewHeroAttributes(
                  tag: '${widget.heroTagPrefix}_$index',
                ),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              );
            },
            backgroundDecoration: const BoxDecoration(color: Colors.transparent),
            loadingBuilder: (_, __) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// 透明背景路由，为图片灯箱提供淡入淡出过渡且保留 Hero 动画效果。
class _TransparentRoute extends PageRoute<void> {
  _TransparentRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}

/// 打开全屏图片灯箱。
void showImageLightbox(
  BuildContext context, {
  required List<String> imageUrls,
  required int initialIndex,
  required String heroTagPrefix,
}) {
  Navigator.of(context, rootNavigator: true).push(
    _TransparentRoute(
      builder: (_) => ImageLightbox(
        imageUrls: imageUrls,
        initialIndex: initialIndex,
        heroTagPrefix: heroTagPrefix,
      ),
    ),
  );
}
