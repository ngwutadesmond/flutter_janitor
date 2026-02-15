import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'models.dart';
import 'path_utils.dart';
import 'pubspec_editor.dart';

class Cleaner {
  Cleaner({PubspecEditor? pubspecEditor})
      : _pubspecEditor = pubspecEditor ?? PubspecEditor();

  final PubspecEditor _pubspecEditor;

  Future<CleanManifest> apply({
    required String projectRoot,
    required CleanActionPlan plan,
    required String backupDir,
  }) async {
    final timestamp = DateTime.now();
    final backupRoot = normalizePath(
      p.isAbsolute(backupDir) ? backupDir : p.join(projectRoot, backupDir),
    );
    await Directory(backupRoot).create(recursive: true);

    final movedEntries = <CleanManifestEntry>[];
    final sortedAssets = plan.assetPaths.toList()..sort();

    for (final relPath in sortedAssets) {
      final sourcePath = normalizePath(p.join(projectRoot, relPath));
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        continue;
      }
      final targetPath = normalizePath(p.join(backupRoot, 'files', relPath));
      await ensureParentDirectory(targetPath);
      await sourceFile.rename(targetPath);
      movedEntries.add(
        CleanManifestEntry(originalPath: sourcePath, backupPath: targetPath),
      );
    }

    final editResult = await _pubspecEditor.removeDependencies(
      projectRoot: projectRoot,
      removeDependencies: plan.removeDependencies,
      removeDevDependencies: plan.removeDevDependencies,
      backupDirectory: backupRoot,
    );

    final manifestPath = normalizePath(
      p.join(backupRoot, 'manifest_${timestamp.millisecondsSinceEpoch}.yaml'),
    );
    final manifest = CleanManifest(
      timestamp: timestamp,
      projectRoot: normalizePath(projectRoot),
      manifestPath: manifestPath,
      movedFiles: movedEntries,
      pubspecBackupPath: editResult.backupPath,
      removedDependencies: editResult.removedDependencies,
      removedDevDependencies: editResult.removedDevDependencies,
    );

    await _writeManifest(manifest);
    return manifest;
  }

  Future<int> undo({required String manifestPath}) async {
    final manifest = await _readManifest(manifestPath);
    var restoredCount = 0;

    for (final entry in manifest.movedFiles) {
      final backup = File(entry.backupPath);
      if (!await backup.exists()) {
        continue;
      }
      await ensureParentDirectory(entry.originalPath);
      await backup.rename(entry.originalPath);
      restoredCount++;
    }

    if (manifest.pubspecBackupPath != null) {
      final backupFile = File(manifest.pubspecBackupPath!);
      final pubspecFile = File(p.join(manifest.projectRoot, 'pubspec.yaml'));
      if (await backupFile.exists()) {
        await pubspecFile.writeAsString(await backupFile.readAsString());
      }
    }

    return restoredCount;
  }

  Future<void> _writeManifest(CleanManifest manifest) async {
    final file = File(manifest.manifestPath);
    await ensureParentDirectory(manifest.manifestPath);

    final buffer = StringBuffer()
      ..writeln('timestamp: ${manifest.timestamp.toIso8601String()}')
      ..writeln('project_root: ${manifest.projectRoot}')
      ..writeln('manifest_path: ${manifest.manifestPath}')
      ..writeln('pubspec_backup: ${manifest.pubspecBackupPath ?? ''}')
      ..writeln('removed_dependencies:');
    buffer.write(_writeList(manifest.removedDependencies).toString());
    buffer
      ..writeln('removed_dev_dependencies:')
      ..write(_writeList(manifest.removedDevDependencies).toString())
      ..writeln('moved_files:');

    for (final moved in manifest.movedFiles) {
      buffer
        ..writeln('  - original: ${moved.originalPath}')
        ..writeln('    backup: ${moved.backupPath}');
    }

    await file.writeAsString(buffer.toString());
  }

  StringBuffer _writeList(Set<String> items, {String indent = '  '}) {
    final buffer = StringBuffer();
    final sorted = items.toList()..sort();
    if (sorted.isEmpty) {
      buffer.writeln('$indent[]');
      return buffer;
    }
    for (final item in sorted) {
      buffer.writeln('$indent- $item');
    }
    return buffer;
  }

  Future<CleanManifest> _readManifest(String manifestPath) async {
    final file = File(manifestPath);
    if (!await file.exists()) {
      throw StateError('Manifest not found: $manifestPath');
    }

    final yaml = loadYaml(await file.readAsString());
    if (yaml is! YamlMap) {
      throw StateError('Invalid manifest format: $manifestPath');
    }

    final movedFiles = <CleanManifestEntry>[];
    final rawMoved = yaml['moved_files'];
    if (rawMoved is YamlList) {
      for (final entry in rawMoved) {
        if (entry is! YamlMap) {
          continue;
        }
        final original = entry['original'];
        final backup = entry['backup'];
        if (original is String && backup is String) {
          movedFiles.add(
            CleanManifestEntry(
              originalPath: normalizePath(original),
              backupPath: normalizePath(backup),
            ),
          );
        }
      }
    }

    final removedDeps = _readYamlStringSet(yaml['removed_dependencies']);
    final removedDevDeps = _readYamlStringSet(yaml['removed_dev_dependencies']);

    final timestampText = yaml['timestamp']?.toString() ?? '';
    final timestamp = DateTime.tryParse(timestampText) ?? DateTime.now();

    final projectRoot = yaml['project_root']?.toString();
    if (projectRoot == null || projectRoot.isEmpty) {
      throw StateError('Manifest missing project_root: $manifestPath');
    }

    final parsedManifestPath =
        yaml['manifest_path']?.toString() ?? manifestPath;
    final pubspecBackup = yaml['pubspec_backup']?.toString();

    return CleanManifest(
      timestamp: timestamp,
      projectRoot: normalizePath(projectRoot),
      manifestPath: normalizePath(parsedManifestPath),
      movedFiles: movedFiles,
      pubspecBackupPath: pubspecBackup == null || pubspecBackup.isEmpty
          ? null
          : normalizePath(pubspecBackup),
      removedDependencies: removedDeps,
      removedDevDependencies: removedDevDeps,
    );
  }

  Set<String> _readYamlStringSet(Object? value) {
    if (value is! YamlList) {
      return <String>{};
    }
    return value
        .whereType<String>()
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet();
  }
}
