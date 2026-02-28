import 'save_image_to_gallery_io.dart' if (dart.library.html) 'save_image_to_gallery_stub.dart' as impl;

/// 根据当前图片 URL 下载并保存到相册（非 Web）；Web 端返回 false，由调用方提示用户。
Future<bool> saveImageFromUrl(String url) => impl.saveImageFromUrl(url);
