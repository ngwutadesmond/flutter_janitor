import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'models.dart';
import 'path_utils.dart';

class PubspecParser {
  static const Set<String> supportedAssetExtensions = {
    '.svg',
    '.png',
    '.jpeg',
    '.jpg',
    '.webp',
    '.json',
    '.yaml',
    '.yml',
    '.ttf',
    '.otf',
    '.woff',
    '.woff2',
  };

  Future<PubspecData> parse(String projectRoot) async {
    final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
    final file = File(pubspecPath);
    if (!await file.exists()) {
      throw StateError('pubspec.yaml not found in $projectRoot');
    }

    final content = await file.readAsString();
    final yaml = loadYaml(content);
    if (yaml is! YamlMap) {
      throw StateError('Invalid pubspec.yaml in $projectRoot');
    }

    final flutterSection = yaml['flutter'];
    final declaredAssets = <String>{};
    final fontFamilies = <String, DeclaredFontFamily>{};

    if (flutterSection is YamlMap) {
      await _parseAssets(flutterSection['assets'], projectRoot, declaredAssets);
      await _parseFonts(
        flutterSection['fonts'],
        projectRoot,
        declaredAssets,
        fontFamilies,
      );
    }

    return PubspecData(
      projectRoot: normalizePath(projectRoot),
      pubspecPath: normalizePath(pubspecPath),
      declaredAssets: declaredAssets,
      fontFamilies: fontFamilies,
      dependencies: _readDependencyMap(yaml['dependencies']),
      devDependencies: _readDependencyMap(yaml['dev_dependencies']),
    );
  }

  Future<void> _parseAssets(
    Object? rawAssets,
    String projectRoot,
    Set<String> declaredAssets,
  ) async {
    if (rawAssets is! YamlList) {
      return;
    }

    for (final entry in rawAssets) {
      if (entry is! String || entry.trim().isEmpty) {
        continue;
      }
      final normalizedEntry = normalizePath(entry.trim());
      final absolutePath = p.join(projectRoot, normalizedEntry);
      final entityType = FileSystemEntity.typeSync(
        absolutePath,
        followLinks: false,
      );

      if (normalizedEntry.endsWith('/') ||
          entityType == FileSystemEntityType.directory) {
        final directory = Directory(
          normalizedEntry.endsWith('/')
              ? absolutePath
              : p.join(projectRoot, '$normalizedEntry/'),
        );
        if (await directory.exists()) {
          await for (final entity in directory.list(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is! File) {
              continue;
            }
            final rel = toProjectRelative(projectRoot, entity.path);
            if (_hasSupportedAssetExtension(rel)) {
              declaredAssets.add(rel);
            }
          }
        }
        continue;
      }

      if (_hasSupportedAssetExtension(normalizedEntry)) {
        declaredAssets.add(normalizedEntry);
      }
    }
  }

  Future<void> _parseFonts(
    Object? rawFonts,
    String projectRoot,
    Set<String> declaredAssets,
    Map<String, DeclaredFontFamily> fontFamilies,
  ) async {
    if (rawFonts is! YamlList) {
      return;
    }

    for (final font in rawFonts) {
      if (font is! YamlMap) {
        continue;
      }
      final familyName = font['family'];
      final fontsList = font['fonts'];
      if (familyName is! String || fontsList is! YamlList) {
        continue;
      }

      final files = <String>{};
      for (final member in fontsList) {
        if (member is! YamlMap) {
          continue;
        }
        final assetPath = member['asset'];
        if (assetPath is! String || assetPath.trim().isEmpty) {
          continue;
        }
        final normalized = normalizePath(assetPath.trim());
        final absolute = p.join(projectRoot, normalized);
        if (await File(absolute).exists()) {
          files.add(normalized);
        } else {
          files.add(normalized);
        }
        declaredAssets.add(normalized);
      }

      fontFamilies[familyName] = DeclaredFontFamily(
        family: familyName,
        files: files,
      );
    }
  }

  Map<String, String> _readDependencyMap(Object? rawDependencies) {
    if (rawDependencies is! YamlMap) {
      return const <String, String>{};
    }

    final map = <String, String>{};
    for (final entry in rawDependencies.entries) {
      final key = entry.key;
      if (key is! String) {
        continue;
      }
      map[key] = '${entry.value ?? ''}'.trim();
    }
    return map;
  }

  bool _hasSupportedAssetExtension(String path) {
    final extension = p.extension(path).toLowerCase();
    return supportedAssetExtensions.contains(extension);
  }
}
