import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
import '../data/files_repository.dart';
import '../data/models/file_model.dart';

final filesRepositoryProvider = Provider<FilesRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return FilesRepository(dio: dio);
});

final filesListProvider = FutureProvider<List<FileModel>>((ref) async {
  final repo = ref.watch(filesRepositoryProvider);
  return repo.fetchFiles();
});
