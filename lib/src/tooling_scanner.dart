import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'models.dart';
import 'project_walker.dart';

class ToolingScanner {
  Future<Map<String, Set<String>>> scanToolingMentions({
    required String projectRoot,
    required Iterable<String> packageNames,
    DartReferenceScanResult? references,
    Set<String> assets = const {},
  }) async {
    final mentions = <String, Set<String>>{};
    final files =
        await ProjectWalker(projectRoot: projectRoot, excludeRoots: {})
            .listProjectFiles(warnings: references?.warnings);
    for (final relative in files) {
      if (relative == 'pubspec.lock') continue;
      final file = File(p.join(projectRoot, relative));
      String content;
      try {
        if (await file.length() > 4 * 1024 * 1024) {
          references?.warnings.add('Large input omitted: $relative');
          continue;
        }
        content = utf8.decode(await file.readAsBytes());
        if (content.contains('\u0000')) continue;
      } on FormatException catch (_) {
        // Binary resources cannot be treated as source text.
        continue;
      } on FileSystemException catch (_) {
        references?.warnings.add('Unreadable input: $relative');
        continue;
      }
      if (relative == 'pubspec.yaml') {
        final yaml = loadYaml(content);
        if (yaml is YamlMap) {
          // The declaration of a dependency alone is not a tooling hit.
          content = {
            for (final e in yaml.entries)
              if (e.key != 'dependencies' && e.key != 'dev_dependencies')
                e.key: e.value
          }.toString();
        }
      } else {
        for (final asset in assets) {
          // Basenames retain native/config references that resolve a directory
          // independently (including CSS URL paths and generated wrappers).
          if (relative != asset &&
              (content.contains(asset) ||
                  content.contains(p.basename(asset)))) {
            references?.usedAssets.add(asset);
          }
        }
      }
      for (final package in packageNames) {
        if (RegExp(
                '(^|[^a-zA-Z0-9_])${RegExp.escape(package)}([^a-zA-Z0-9_]|\$)')
            .hasMatch(content)) {
          mentions.putIfAbsent(package, () => <String>{}).add(relative);
        }
      }
    }
    return mentions;
  }
}
