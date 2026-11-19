import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import 'importer.dart';
import 'library_repository.dart';
import '../domain/media_item.dart';

final mediaImporterProvider = Provider<MediaImporter>((ref) => MediaImporter());

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(ref.read(databaseProvider));
});

/// 首页「继续收听 / 继续观看」列表（audio | video）
final continueListProvider =
    FutureProvider.family<List<MediaItem>, String>((ref, type) {
  return ref.read(libraryRepositoryProvider).continueList(type);
});
