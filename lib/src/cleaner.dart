import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'models.dart';
import 'path_utils.dart';
import 'pubspec_editor.dart';
import 'pubspec_parser.dart';

/// Journaled cleanup. Backups and the complete recovery journal are flushed
/// before the first change. Use only on a quiescent project filesystem.
class Cleaner {
  Cleaner({PubspecEditor? pubspecEditor, this.checkpoint})
      : _pubspecEditor = pubspecEditor ?? PubspecEditor();
  final PubspecEditor _pubspecEditor;

  /// Optional fault-injection hook for recovery tests and embedding clients.
  final Future<void> Function(String phase)? checkpoint;

  Future<T> _locked<T>(String root, Future<T> Function() action) async {
    final lock = await File(checkedPath(root, '.janitor-lock'))
        .open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      return await action();
    } finally {
      await lock.close();
    }
  }

  Future<CleanManifest> apply(
      {required String projectRoot,
      required CleanActionPlan plan,
      required String backupDir}) {
    final root = checkedRoot(projectRoot);
    return _locked(root,
        () => _apply(projectRoot: root, plan: plan, backupDir: backupDir));
  }

  Future<CleanManifest> _apply(
      {required String projectRoot,
      required CleanActionPlan plan,
      required String backupDir}) async {
    final root = projectRoot;
    final pubspec = await PubspecParser().parse(root);
    if (pubspec.reportOnlyReasons.isNotEmpty) {
      throw StateError(pubspec.reportOnlyReasons.join(' '));
    }
    final backupRoot = checkedProjectPath(root, backupDir);
    if (p.basename(backupRoot) == 'pubspec.yaml') {
      throw StateError('Invalid backup directory');
    }
    final originalPubspecBytes =
        await File(checkedPath(root, 'pubspec.yaml')).readAsBytes();
    final originalPubspec = utf8.decode(originalPubspecBytes);
    final updatedPubspec = _pubspecEditor.edit(originalPubspec, plan);
    final hadBom = originalPubspecBytes.length >= 3 &&
        originalPubspecBytes[0] == 239 &&
        originalPubspecBytes[1] == 187 &&
        originalPubspecBytes[2] == 191;
    final updatedBytes = <int>[
      if (hadBom) ...[239, 187, 191],
      ...utf8.encode(updatedPubspec)
    ];
    final sources = <String, List<int>>{};
    for (final relative in plan.assetPaths.toList()..sort()) {
      final path = checkedPath(root, relative);
      _checkRecoveryTarget(relative);
      if (!pubspec.declaredAssets.contains(relative) ||
          pubspec.assetReasons.containsKey(relative)) {
        throw StateError('Asset is undeclared or protected: $relative');
      }
      if (p.isWithin(backupRoot, path) ||
          p.isWithin(path, backupRoot) ||
          path == backupRoot) {
        throw StateError('Backup directory overlaps asset: $relative');
      }
      sources[relative] = await File(path).readAsBytes();
    }
    if (updatedPubspec != originalPubspec) {
      sources['pubspec.yaml'] = originalPubspecBytes;
    }
    if (sources.isEmpty) throw StateError('No changes selected');
    await Directory(backupRoot).create(recursive: true);
    final operation = await Directory(backupRoot).createTemp('operation-');
    final operationRelative = portableRelativePath(operation.path, from: root);
    final journalPath = p.join(operation.path, 'manifest.json');
    final entries = <Map<String, dynamic>>[];
    // No project mutations occur until every backup and the journal exist.
    for (final source in sources.entries) {
      final backup =
          checkedPath(root, '$operationRelative/before/${source.key}');
      await ensureParentDirectory(backup);
      await File(checkedPath(root, source.key)).copy(backup);
      final handle = await File(backup).open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      if (_hash(await File(backup).readAsBytes()) != _hash(source.value)) {
        throw StateError('Source changed while backing up: ${source.key}');
      }
      entries.add({
        'path': source.key,
        'before': _hash(source.value),
        'mode': (await File(checkedPath(root, source.key)).stat()).mode & 511,
        'after': source.key == 'pubspec.yaml' ? _hash(updatedBytes) : null
      });
    }
    final journal = <String, dynamic>{
      'version': 2,
      'project_root': root,
      'operation': operationRelative,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'entries': entries,
      'removed_dependencies': plan.removeDependencies.toList()..sort(),
      'removed_dev_dependencies': plan.removeDevDependencies.toList()..sort()
    };
    await checkpoint?.call('before-journal:$journalPath');
    await File(journalPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(journal),
        flush: true);
    await checkpoint?.call('journal-ready');
    try {
      if (_hash(await File(checkedPath(root, 'pubspec.yaml')).readAsBytes()) !=
          _hash(originalPubspecBytes)) {
        throw StateError('pubspec.yaml changed while preparing cleanup');
      }
      // Recheck the complete snapshot after backups are durable, before mutation.
      for (final entry in entries) {
        final file = File(checkedPath(root, entry['path'] as String));
        if (_hash(await file.readAsBytes()) != entry['before']) {
          throw StateError(
              'Project changed while preparing cleanup: ${entry['path']}');
        }
      }
      for (final entry in entries) {
        final path = checkedPath(root, entry['path'] as String);
        if (entry['after'] == null) {
          await File(path).delete();
        } else {
          await _replace(root, entry['path'] as String, updatedBytes,
              template:
                  checkedPath(root, '$operationRelative/before/pubspec.yaml'),
              mode: entry['mode'] as int);
        }
        await checkpoint?.call('changed:${entry['path']}');
      }
      await checkpoint?.call('applied');
    } catch (error) {
      try {
        await _undo(manifestPath: journalPath, projectRoot: root);
      } catch (restoreError) {
        throw StateError(
            'Cleanup failed: $error. Automatic recovery stopped: $restoreError. Recovery journal: $journalPath');
      }
      throw StateError(
          'Cleanup failed and was rolled back: $error. Recovery journal: $journalPath');
    }
    return CleanManifest(
        timestamp: DateTime.parse(journal['timestamp'] as String),
        projectRoot: root,
        manifestPath: journalPath,
        movedFiles: [
          for (final relative in plan.assetPaths)
            CleanManifestEntry(
                originalPath: checkedPath(root, relative),
                backupPath:
                    checkedPath(root, '$operationRelative/before/$relative'))
        ],
        pubspecBackupPath: sources.containsKey('pubspec.yaml')
            ? checkedPath(root, '$operationRelative/before/pubspec.yaml')
            : null,
        removedDependencies: plan.removeDependencies,
        removedDevDependencies: plan.removeDevDependencies);
  }

  /// Restore into the explicitly bound project (defaults to the current one).
  /// All conflicts and backup hashes are checked before restoring any file.
  /// Backups are retained, so undo is repeatable after interruption.
  Future<int> undo({required String manifestPath, String? projectRoot}) {
    final root = checkedRoot(projectRoot ?? Directory.current.path);
    return _locked(
        root, () => _undo(manifestPath: manifestPath, projectRoot: root));
  }

  Future<int> _undo(
      {required String manifestPath, required String projectRoot}) async {
    final root = projectRoot;
    final actualManifest = checkedProjectPath(root, manifestPath);
    final raw = jsonDecode(await File(actualManifest).readAsString());
    if (raw is! Map<String, dynamic> ||
        raw['version'] != 2 ||
        raw['project_root'] != root) {
      throw StateError(
          'Unsupported or wrong-project recovery journal. Legacy manifests require manual recovery.');
    }
    final operationRelative = raw['operation'];
    if (operationRelative is! String ||
        checkedPath(root, '$operationRelative/manifest.json') !=
            actualManifest) {
      throw StateError('Recovery journal location mismatch');
    }
    final entries = raw['entries'];
    if (entries is! List || entries.isEmpty) {
      throw StateError('Invalid recovery entries');
    }
    final pending = <String, List<int>>{};
    final seen = <String>{};
    for (final entry in entries) {
      if (entry is! Map ||
          entry['path'] is! String ||
          entry['before'] is! String ||
          entry['mode'] is! int ||
          (entry['mode'] as int) < 0 ||
          (entry['mode'] as int) > 511 ||
          (entry['after'] != null && entry['after'] is! String)) {
        throw StateError('Invalid recovery entry');
      }
      final relative = entry['path'] as String;
      final target = checkedPath(root, relative);
      _checkRecoveryTarget(relative, allowPubspec: true);
      if (!seen.add(relative) ||
          p.isWithin(checkedPath(root, operationRelative), target)) {
        throw StateError('Invalid duplicate/overlapping recovery path');
      }
      // Only pubspec may be replaced. Asset recovery may only create a missing
      // file or recognize an identical already-restored file.
      if ((relative == 'pubspec.yaml') != (entry['after'] != null)) {
        throw StateError('Invalid recovery operation');
      }
      final bytes =
          await File(checkedPath(root, '$operationRelative/before/$relative'))
              .readAsBytes();
      if (_hash(bytes) != entry['before']) {
        throw StateError('Corrupt backup: $relative');
      }
      final type = await FileSystemEntity.type(target, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw StateError('Restore destination conflict: $relative');
      }
      final current = type == FileSystemEntityType.file
          ? _hash(await File(target).readAsBytes())
          : null;
      if (current == entry['before']) continue;
      if (current != entry['after']) {
        throw StateError('Restore would overwrite a changed file: $relative');
      }
      pending[relative] = bytes;
    }
    for (final entry in pending.entries) {
      await _replace(root, entry.key, entry.value,
          template: checkedPath(root, '$operationRelative/before/${entry.key}'),
          mode: entries
              .cast<Map>()
              .singleWhere((e) => e['path'] == entry.key)['mode'] as int);
      await checkpoint?.call('restored:${entry.key}');
    }
    return pending.keys.where((key) => key != 'pubspec.yaml').length;
  }

  void _checkRecoveryTarget(String relative, {bool allowPubspec = false}) {
    if (relative.split('/').any((part) => part.startsWith('.')) ||
        relative == 'pubspec.lock' ||
        (!allowPubspec && relative == 'pubspec.yaml')) {
      throw StateError('Protected cleanup/recovery target: $relative');
    }
  }

  Future<void> _replace(String root, String relative, List<int> bytes,
      {required String template, required int mode}) async {
    final target = checkedPath(root, relative);
    await ensureParentDirectory(target);
    // Stage next to the destination: rename stays on the same filesystem even
    // when the backup directory is on a different mounted device.
    final temporary =
        await Directory(p.dirname(target)).createTemp('.janitor-write-');
    try {
      final staged = File(p.join(temporary.path, 'content'));
      await File(template).copy(staged.path);
      if (_hash(await staged.readAsBytes()) != _hash(bytes)) {
        await staged.writeAsBytes(bytes, flush: true);
      }
      if (!Platform.isWindows) {
        final permissions =
            await Process.run('chmod', [mode.toRadixString(8), staged.path]);
        if (permissions.exitCode != 0) {
          throw StateError('Cannot preserve permissions for $relative');
        }
      }
      checkedPath(root, relative);
      await staged.rename(target);
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  String _hash(List<int> bytes) => sha256.convert(bytes).toString();
}
