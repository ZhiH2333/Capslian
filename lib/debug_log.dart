import 'debug_log_stub.dart' if (dart.library.io) 'debug_log_io.dart' as impl;

/// 调试会话日志：写入 NDJSON 到 .cursor/debug-5b5949.log（仅非 web 平台）。
void debugLog(String location, String message, Map<String, dynamic> data, String hypothesisId) {
  impl.debugLog(location, message, data, hypothesisId);
}
