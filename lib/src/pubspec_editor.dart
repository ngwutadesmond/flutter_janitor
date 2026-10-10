import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'models.dart';
import 'path_utils.dart';

class PubspecEditResult {
  const PubspecEditResult(
      {required this.updated,
      this.backupPath,
      this.removedDependencies = const {},
      this.removedDevDependencies = const {}});
  final bool updated;
  final String? backupPath;
  final Set<String> removedDependencies;
  final Set<String> removedDevDependencies;
}

/// Computes and semantically validates edits before any project file is written.
class PubspecEditor {
  String edit(String original, CleanActionPlan plan) {
    final parsed = loadYaml(original);
    if (parsed is! YamlMap) throw StateError('pubspec.yaml must be a map');
    final expected = _plain(parsed) as Map;
    final editor = YamlEditor(original);
    for (final section in ['dependencies', 'dev_dependencies']) {
      final removals = section == 'dependencies'
          ? plan.removeDependencies
          : plan.removeDevDependencies;
      for (final name in removals) {
        final map = expected[section];
        if (map is! Map || !map.containsKey(name)) {
          throw StateError('Dependency no longer declared: $section/$name');
        }
        editor.remove([section, name]);
        map.remove(name);
      }
    }
    final flutter = expected['flutter'];
    if (flutter is Map) {
      final fonts = flutter['fonts'];
      if (fonts is List) {
        for (final family in fonts.whereType<Map>()) {
          for (final font
              in (family['fonts'] as List? ?? []).whereType<Map>()) {
            if (plan.assetPaths.contains(font['asset'])) {
              throw StateError(
                  'Declared fonts are protected: ${font['asset']}');
            }
          }
        }
      }
      final assets = flutter['assets'];
      if (assets is List) {
        for (var i = assets.length - 1; i >= 0; i--) {
          final entry = assets[i];
          final path = entry is String
              ? entry
              : entry is Map
                  ? entry['path']
                  : null;
          if (path is String && plan.assetPaths.contains(normalizePath(path))) {
            if (entry is Map) {
              throw StateError(
                  'Configured asset declarations are protected: $path');
            }
            editor.remove(['flutter', 'assets', i]);
            assets.removeAt(i);
          }
        }
      }
    }
    var updated = editor.toString();
    if (original.contains('\r\n')) {
      updated = updated.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
    }
    if (_canonical(_plain(loadYaml(updated))) != _canonical(expected)) {
      throw StateError(
          'Refusing edit: unrelated pubspec semantics would change (possibly YAML aliases).');
    }
    return updated;
  }

  /// Compatibility helper. Cleanup itself uses the journaled transaction.
  Future<PubspecEditResult> removeDependencies(
      {required String projectRoot,
      required Set<String> removeDependencies,
      required Set<String> removeDevDependencies,
      required String backupDirectory}) async {
    final root = checkedRoot(projectRoot);
    final file = File(checkedPath(root, 'pubspec.yaml'));
    final original = await file.readAsString();
    final updated = edit(
        original,
        CleanActionPlan(
            assetPaths: {},
            removeDependencies: removeDependencies,
            removeDevDependencies: removeDevDependencies));
    if (original == updated) return const PubspecEditResult(updated: false);
    final backupRel = p.relative(p.absolute(backupDirectory), from: root);
    final directory =
        await Directory(checkedPath(root, backupRel)).create(recursive: true);
    final operation = await directory.createTemp('pubspec-');
    final backup = File(p.join(operation.path, 'pubspec.yaml'));
    await backup.writeAsString(original, flush: true);
    final staging = File(p.join(operation.path, 'updated.yaml'));
    await staging.writeAsString(updated, flush: true);
    await staging.rename(file.path);
    return PubspecEditResult(
        updated: true,
        backupPath: backup.path,
        removedDependencies: removeDependencies,
        removedDevDependencies: removeDevDependencies);
  }

  Object? _plain(Object? value) {
    if (value is Map) {
      return {for (final e in value.entries) e.key: _plain(e.value)};
    }
    if (value is List) return value.map(_plain).toList();
    return value;
  }

  String _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.toList()
        ..sort((a, b) => _canonical(a).compareTo(_canonical(b)));
      return '{${keys.map((k) => '${_canonical(k)}:${_canonical(value[k])}').join(',')}}';
    }
    if (value is List) return '[${value.map(_canonical).join(',')}]';
    return jsonEncode(value);
  }
}
