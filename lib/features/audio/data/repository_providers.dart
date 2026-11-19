import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import 'importer.dart';
import 'library_repository.dart';

final mediaImporterProvider = Provider<MediaImporter>((ref) => MediaImporter());

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(ref.read(databaseProvider));
});
