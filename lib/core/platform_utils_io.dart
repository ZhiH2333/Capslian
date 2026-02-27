import 'dart:io' show Platform;

/// 有 dart:io 时（macOS/Windows/Linux 等）使用。
bool get isDesktopMacOS => Platform.isMacOS;
bool get isDesktopWindows => Platform.isWindows;
