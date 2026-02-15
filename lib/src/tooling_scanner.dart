import 'dart:io';

import 'package:path/path.dart' as p;

import 'path_utils.dart';

class ToolingScanner {
  static const List<String> _rootFiles = [
    'build.yaml',
    'build_runner.yaml',
    'analysis_options.yaml',
    'melos.yaml',
    'pubspec_overrides.yaml',
  ];

  Future<Map<String, Set<String>>> scanToolingMentions({
    required String projectRoot,
    required Iterable<String> packageNames,
  }) async {
    final mentions = <String, Set<String>>{};
    final candidates = <String>{..._rootFiles};

    for (final dirName in const ['tool', 'scripts']) {
      final dir = Directory(p.join(projectRoot, dirName));
      if (!await dir.exists()) {
        continue;
      }
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final rel = toProjectRelative(projectRoot, entity.path);
        candidates.add(rel);
      }
    }

    final sortedCandidates = candidates.toList()..sort();
    final packageRegexes = <String, RegExp>{
      for (final package in packageNames)
        package: RegExp(
          '(^|[^a-zA-Z0-9_])${RegExp.escape(package)}([^a-zA-Z0-9_]|\\\$)',
        ),
    };

    for (final relPath in sortedCandidates) {
      final file = File(p.join(projectRoot, relPath));
      if (!await file.exists()) {
        continue;
      }
      final content = await file.readAsString();
      for (final package in packageNames) {
        final regex = packageRegexes[package]!;
        if (regex.hasMatch(content)) {
          mentions
              .putIfAbsent(package, () => <String>{})
              .add(normalizePath(relPath));
        }
      }
    }

    return mentions;
  }
}
