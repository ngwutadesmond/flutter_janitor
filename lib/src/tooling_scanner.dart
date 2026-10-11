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
      var assetContent = content;
      var configPaths = <String>[];
      if (relative == 'pubspec.yaml') {
        final yaml = loadYaml(content);
        if (yaml is YamlMap) {
          // The declaration of a dependency alone is not a tooling hit.
          content = {
            for (final e in yaml.entries)
              if (e.key != 'dependencies' && e.key != 'dev_dependencies')
                e.key: e.value
          }.toString();
          final assetConsumers = Map<Object?, Object?>.from(yaml);
          final flutter = yaml['flutter'];
          if (flutter is YamlMap) {
            final consumers = Map<Object?, Object?>.from(flutter);
            final declarations = flutter['assets'];
            // Only ordinary bundle declarations lack independent usage evidence.
            // Keep all other consumers, including licenses, shaders, deferred
            // assets and configuration nested in map-valued asset declarations.
            if (declarations is YamlList) {
              consumers['assets'] =
                  declarations.where((entry) => entry is! String).toList();
            }
            assetConsumers['flutter'] = consumers;
          }
          assetContent = assetConsumers.toString();
          configPaths = _strings(assetConsumers).toList();
        }
      }
      for (final asset in assets) {
        // Basenames retain native/config references that resolve a directory
        // independently (including CSS URL paths and generated wrappers).
        if (relative != asset &&
            (assetContent.contains(asset) ||
                assetContent.contains(p.basename(asset)) ||
                configPaths.any(
                    (path) => path.endsWith('/') && asset.startsWith(path)))) {
          references?.usedAssets.add(asset);
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

  Iterable<String> _strings(Object? value) sync* {
    if (value is String) yield value;
    if (value is Map) {
      for (final entry in value.values) {
        yield* _strings(entry);
      }
    }
    if (value is Iterable) {
      for (final entry in value) {
        yield* _strings(entry);
      }
    }
  }
}
