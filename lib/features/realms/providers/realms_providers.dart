import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
import '../data/realms_repository.dart';
import '../data/models/realm_model.dart';

final realmsRepositoryProvider = Provider<RealmsRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return RealmsRepository(dio: dio);
});

final realmsListProvider = FutureProvider<List<RealmModel>>((ref) async {
  final repo = ref.watch(realmsRepositoryProvider);
  return repo.fetchRealms();
});

final realmDetailProvider = FutureProvider.family<RealmModel?, String>((ref, id) async {
  final repo = ref.watch(realmsRepositoryProvider);
  return repo.getRealm(id);
});
