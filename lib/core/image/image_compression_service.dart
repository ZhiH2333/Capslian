import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'image_compression_io.dart' if (dart.library.html) 'image_compression_stub.dart' as io;

/// 图片压缩服务：将图片压缩到目标体积；支持写入临时文件（非 Web）或返回字节（Web 通用）。
class ImageCompressionService {
  ImageCompressionService._();

  /// 将 [sourcePath] 压缩到约 [maxBytesKb] KB 以内并写入临时文件。仅非 Web 平台。
  static Future<String> compressToFile(
    String sourcePath, {
    required int maxBytesKb,
    int? maxWidth,
    int? maxHeight,
  }) =>
      io.compressToFileImpl(
        sourcePath,
        maxBytesKb: maxBytesKb,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );

  /// 将 [bytes] 压缩到约 [maxBytesKb] KB 以内，返回压缩后的字节。Web 与各平台通用。
  static Future<Uint8List> compressToBytes(
    Uint8List bytes, {
    required int maxBytesKb,
    int? maxWidth,
    int? maxHeight,
  }) async {
    final maxBytes = maxBytesKb * 1024;
    final width = maxWidth ?? 1920;
    final height = maxHeight ?? 1080;
    final qualities = <int>[85, 70, 55, 40, 25, 15];
    Uint8List? lastResult;
    for (final q in qualities) {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: width,
        minHeight: height,
        quality: q,
        format: CompressFormat.jpeg,
      );
      lastResult = result;
      if (result.length <= maxBytes) break;
    }
    final out = lastResult;
    if (out == null) throw Exception('图片压缩失败');
    return out;
  }
}
