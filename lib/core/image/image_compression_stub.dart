/// Web 平台占位：不支持基于路径的压缩，请使用 [ImageCompressionService.compressToBytes]。
Future<String> compressToFileImpl(
  String sourcePath, {
  required int maxBytesKb,
  int? maxWidth,
  int? maxHeight,
}) async {
  throw UnsupportedError('Web 端请使用 ImageCompressionService.compressToBytes');
}
