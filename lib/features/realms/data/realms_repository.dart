import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import 'models/realm_model.dart';

/// 圈子接口：列表、详情、加入、退出。
class RealmsRepository {
  RealmsRepository({required Dio dio}) : _dio = dio;
  final Dio _dio;

  Future<List<RealmModel>> fetchRealms() async {
    final response = await _dio.get<Map<String, dynamic>>(ApiConstants.realms);
    final data = response.data;
    if (data == null || data['realms'] is! List) return [];
    return (data['realms'] as List)
        .map((e) => RealmModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RealmModel?> getRealm(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(ApiConstants.realmById(id));
      final data = response.data;
      if (data == null || data['realm'] == null) return null;
      return RealmModel.fromJson(data['realm'] as Map<String, dynamic>);
    } on DioException catch (_) {
      return null;
    }
  }

  Future<void> joinRealm(String realmId) async {
    await _dio.post<Map<String, dynamic>>(ApiConstants.realmJoin(realmId));
  }

  Future<void> leaveRealm(String realmId) async {
    await _dio.post<Map<String, dynamic>>(ApiConstants.realmLeave(realmId));
  }
}
