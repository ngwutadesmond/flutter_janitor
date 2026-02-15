import 'dart:io';

import 'package:path/path.dart' as p;

import 'path_utils.dart';

class ProjectWalker {
  ProjectWalker({required this.projectRoot, required this.excludeRoots});

  final String projectRoot;
  final Set<String> excludeRoots;

  Future<List<String>> listDartFiles({
    required Set<String> includeRoots,
  }) async {
    final files = <String>[];
    final roots = <String>{
      'lib',
      ...includeRoots,
    }.map(normalizePath).where((entry) => entry.isNotEmpty).toList()
      ..sort();

    for (final root in roots) {
      final directory = Directory(p.join(projectRoot, root));
      if (!await directory.exists()) {
        continue;
      }
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) {
          continue;
        }
        if (!entity.path.endsWith('.dart')) {
          continue;
        }
        final rel = toProjectRelative(projectRoot, entity.path);
        if (isWithinExcludedRoot(rel, excludeRoots)) {
          continue;
        }
        files.add(rel);
      }
    }

    files.sort();
    return files;
  }

  Future<List<String>> listFilesUnder(String relativeDirectory) async {
    final directory = Directory(p.join(projectRoot, relativeDirectory));
    if (!await directory.exists()) {
      return <String>[];
    }

    final results = <String>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      final rel = toProjectRelative(projectRoot, entity.path);
      if (isWithinExcludedRoot(rel, excludeRoots)) {
        continue;
      }
      results.add(rel);
    }
    results.sort();
    return results;
  }
}
