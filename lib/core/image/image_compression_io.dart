import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 仅在支持 dart:io 的平台使用：将图片压缩并写入临时文件。
Future<String> compressToFileImpl(
  String sourcePath, {
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
    final result = await FlutterImageCompress.compressWithFile(
      sourcePath,
      minWidth: width,
      minHeight: height,
      quality: q,
      format: CompressFormat.jpeg,
    );
    if (result == null) continue;
    lastResult = result;
    if (result.length <= maxBytes) break;
  }
  if (lastResult == null) {
    throw Exception('图片压缩失败');
  }
  final dir = await getTemporaryDirectory();
  final name = 'upload_${DateTime.now().millisecondsSinceEpoch}.jpg';
  final targetPath = p.join(dir.path, name);
  final file = File(targetPath);
  await file.writeAsBytes(lastResult);
  return targetPath;
}
