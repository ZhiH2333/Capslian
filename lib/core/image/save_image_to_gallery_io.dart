import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';

/// 非 Web 平台：请求相册权限后下载图片并保存到相册。
/// iOS 需在 Info.plist 中配置 NSPhotoLibraryAddUsageDescription。
/// 若当前平台未实现权限或相册插件（如部分桌面/模拟器），会捕获 MissingPluginException 并返回 false。
Future<bool> saveImageFromUrl(String url) async {
  try {
    final PermissionStatus status = await Permission.photos.request();
    if (!status.isGranted) {
      final PermissionStatus storageStatus = await Permission.storage.request();
      if (!storageStatus.isGranted) return false;
    }
  } on MissingPluginException catch (_) {
  } on PlatformException catch (_) {
  }
  final Dio dio = Dio();
  try {
    final Response<List<int>> response = await dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final List<int>? data = response.data;
    if (data == null || data.isEmpty) return false;
    final Map<String, dynamic>? result =
        await ImageGallerySaver.saveImage(Uint8List.fromList(data));
    return result?['isSuccess'] == true;
  } on MissingPluginException catch (_) {
    return false;
  } on PlatformException catch (_) {
    return false;
  } catch (_) {
    return false;
  }
}
