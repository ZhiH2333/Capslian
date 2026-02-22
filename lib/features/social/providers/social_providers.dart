import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
import '../data/social_repository.dart';

final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return SocialRepository(dio: dio);
});
