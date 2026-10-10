import 'dart:io';
import 'package:path/path.dart' as p;
import 'path_utils.dart';

/// Enumerates project inputs without following links or descending caches.
class ProjectWalker {
  ProjectWalker({required this.projectRoot, required this.excludeRoots});
  final String projectRoot;
  final Set<String> excludeRoots;
  static const cacheNames = {
    '.git',
    '.dart_tool',
    '.pub',
    'build',
    '.janitor_backup',
    'node_modules',
    'Pods',
    '.gradle',
    '.symlinks'
  };

  Future<List<String>> listProjectFiles({Set<String>? warnings}) async {
    final results = <String>[];
    Future<void> visit(Directory directory) async {
      try {
        await for (final entity in directory.list(followLinks: false)) {
          final rel = toProjectRelative(projectRoot, entity.path);
          if (entity is Link) {
            warnings?.add('Symlink input was not followed: $rel');
          } else if (entity is Directory) {
            if (!cacheNames.contains(p.basename(entity.path))) {
              await visit(entity);
            }
          } else if (entity is File) {
            results.add(rel);
          }
        }
      } on FileSystemException catch (_) {
        warnings?.add(
            'Unreadable directory: ${toProjectRelative(projectRoot, directory.path)}');
      }
    }

    await visit(Directory(checkedRoot(projectRoot)));
    results.sort();
    return results;
  }

  Future<List<String>> listDartFiles(
          {required Set<String> includeRoots}) async =>
      (await listProjectFiles())
          .where((file) => file.endsWith('.dart'))
          .toList();

  Future<List<String>> listFilesUnder(String relativeDirectory) async {
    checkedPath(projectRoot, relativeDirectory);
    return (await listProjectFiles())
        .where((file) => p.isWithin(relativeDirectory, file))
        .toList();
  }
}
