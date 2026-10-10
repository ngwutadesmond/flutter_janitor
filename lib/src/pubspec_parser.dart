import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'models.dart';
import 'path_utils.dart';

class PubspecParser {
  static const supportedAssetExtensions = {
    '.svg',
    '.png',
    '.jpeg',
    '.jpg',
    '.webp',
    '.gif',
    '.bmp',
    '.json',
    '.yaml',
    '.yml',
    '.ttf',
    '.otf',
    '.woff',
    '.woff2',
    '.txt',
    '.csv',
    '.mp3',
    '.mp4',
    '.wav',
    '.html',
    '.xml',
    '.bin',
    '.pdf',
    '.frag',
  };
  static final variantDirectory = RegExp(r'^\d+(?:\.\d+)?x$');

  Future<PubspecData> parse(String projectRoot) async {
    final root = checkedRoot(projectRoot);
    final pubspecPath = checkedPath(root, 'pubspec.yaml');
    final file = File(pubspecPath);
    if (!await file.exists()) {
      throw StateError('pubspec.yaml not found in $root');
    }
    final yaml = loadYaml(await file.readAsString());
    if (yaml is! YamlMap) throw StateError('Invalid pubspec.yaml in $root');
    final declared = <String>{};
    final fonts = <String, DeclaredFontFamily>{};
    final reasons = <String, String>{};
    final reportOnly = <String>{};
    final effective = <Object?, Object?>{...yaml, ...await _overrides(root)};
    if (effective.containsKey('workspace') ||
        effective['resolution'] == 'workspace') {
      reportOnly.add(
          'Pub workspaces are report-only; shared resolution files require workspace-level recovery.');
    }
    // A member can be invoked before its resolution field has been configured.
    var ancestor = Directory(root).parent;
    while (ancestor.path != ancestor.parent.path) {
      final ancestorPubspec = File(p.join(ancestor.path, 'pubspec.yaml'));
      if (await ancestorPubspec.exists()) {
        final parent = loadYaml(await ancestorPubspec.readAsString());
        final effectiveParent = <Object?, Object?>{
          if (parent is YamlMap) ...parent,
          ...await _overrides(ancestor.path)
        };
        if (effectiveParent.containsKey('workspace')) {
          reportOnly.add(
              'Project lies inside a Pub workspace; cleanup is report-only.');
        }
      }
      ancestor = ancestor.parent;
    }
    final flutter = yaml['flutter'];
    if (flutter != null && flutter is! YamlMap) {
      throw StateError('flutter must be a mapping');
    }
    if (flutter is YamlMap) {
      final rawAssets = flutter['assets'];
      if (rawAssets != null && rawAssets is! YamlList) {
        throw StateError('flutter.assets must be a list');
      }
      if (rawAssets is YamlList) {
        for (final entry in rawAssets) {
          final path = entry is String
              ? entry
              : entry is YamlMap
                  ? entry['path']
                  : null;
          if (path is! String || path.isEmpty) {
            throw StateError('Unsupported asset declaration: $entry');
          }
          await _expand(
              root,
              path,
              declared,
              reasons,
              entry is YamlMap
                  ? 'Configured asset (platforms, flavors or transformers); preserve declaration.'
                  : null);
        }
      }
      final rawFonts = flutter['fonts'];
      if (rawFonts != null && rawFonts is! YamlList) {
        throw StateError('flutter.fonts must be a list');
      }
      if (rawFonts is YamlList) {
        for (final family in rawFonts) {
          if (family is! YamlMap ||
              family['family'] is! String ||
              family['fonts'] is! YamlList) {
            throw StateError('Unsupported font declaration');
          }
          final files = <String>{};
          for (final member in family['fonts'] as YamlList) {
            if (member is! YamlMap || member['asset'] is! String) {
              throw StateError('Invalid font asset');
            }
            final path = member['asset'] as String;
            if (!path.startsWith('packages/')) checkedPath(root, path);
            files.add(normalizePath(path));
            declared.add(normalizePath(path));
            reasons[normalizePath(path)] =
                'Declared font: runtime family selection and fallback cannot establish non-use.';
          }
          fonts[family['family'] as String] = DeclaredFontFamily(
              family: family['family'] as String, files: files);
        }
      }
    }
    return PubspecData(
        projectRoot: root,
        pubspecPath: pubspecPath,
        declaredAssets: declared,
        fontFamilies: fonts,
        dependencies: _dependencies(yaml['dependencies']),
        devDependencies: _dependencies(yaml['dev_dependencies']),
        assetReasons: reasons,
        reportOnlyReasons: reportOnly);
  }

  Future<Map> _overrides(String root) async {
    final file = File(checkedPath(root, 'pubspec_overrides.yaml'));
    if (!await file.exists()) return {};
    final yaml = loadYaml(await file.readAsString());
    if (yaml == null) return {};
    if (yaml is! YamlMap) {
      throw StateError('Invalid pubspec_overrides.yaml in $root');
    }
    return yaml;
  }

  Future<void> _expand(String root, String raw, Set<String> files,
      Map<String, String> reasons, String? reason) async {
    final rel = normalizePath(raw);
    final absolute = checkedPath(root, raw);
    void add(String path, [String? specific]) {
      files.add(path);
      if (specific ?? reason case final String text) reasons[path] = text;
    }

    if (raw.endsWith('/') || Directory(absolute).existsSync()) {
      if (!Directory(absolute).existsSync()) {
        add(rel, 'Missing declared directory; manual investigation required.');
        return;
      }
      await for (final entity in Directory(absolute).list(followLinks: false)) {
        if (entity is Link) {
          throw StateError('Symlink asset declaration: ${entity.path}');
        }
        if (entity is File) add(toProjectRelative(root, entity.path));
        if (entity is Directory &&
            variantDirectory.hasMatch(p.basename(entity.path))) {
          await for (final variant in entity.list(followLinks: false)) {
            if (variant is Link) {
              throw StateError('Symlink asset variant: ${variant.path}');
            }
            if (variant is File) {
              add(toProjectRelative(root, variant.path),
                  'Resolution variant; retained with its logical image.');
              add(normalizePath(p.join(rel, p.basename(variant.path))),
                  'Logical image has resolution variants; review the group manually.');
            }
          }
        }
      }
    } else {
      add(rel);
      final parent = Directory(p.dirname(absolute));
      if (await parent.exists()) {
        await for (final entity in parent.list(followLinks: false)) {
          if (entity is Directory &&
              variantDirectory.hasMatch(p.basename(entity.path))) {
            final variant = checkedPath(root,
                toProjectRelative(root, p.join(entity.path, p.basename(rel))));
            if (File(variant).existsSync()) {
              add(toProjectRelative(root, variant),
                  'Resolution variant; retained with its logical image.');
              reasons[rel] =
                  'Logical image has resolution variants; review the group manually.';
            }
          }
        }
      }
    }
  }

  Map<String, String> _dependencies(Object? raw) {
    if (raw == null) return {};
    if (raw is! YamlMap || raw.keys.any((key) => key is! String)) {
      throw StateError('Dependencies must be a string-keyed mapping');
    }
    return {
      for (final entry in raw.entries) entry.key as String: '${entry.value}'
    };
  }
}
