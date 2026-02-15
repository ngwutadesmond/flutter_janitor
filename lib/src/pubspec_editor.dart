import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'path_utils.dart';

class PubspecEditResult {
  const PubspecEditResult({
    required this.updated,
    this.backupPath,
    this.removedDependencies = const <String>{},
    this.removedDevDependencies = const <String>{},
  });

  final bool updated;
  final String? backupPath;
  final Set<String> removedDependencies;
  final Set<String> removedDevDependencies;
}

class PubspecEditor {
  Future<PubspecEditResult> removeDependencies({
    required String projectRoot,
    required Set<String> removeDependencies,
    required Set<String> removeDevDependencies,
    required String backupDirectory,
  }) async {
    if (removeDependencies.isEmpty && removeDevDependencies.isEmpty) {
      return const PubspecEditResult(updated: false);
    }

    final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
    final file = File(pubspecPath);
    final original = await file.readAsString();
    final lines = original.split('\n');

    final depRanges = _collectEntryRanges(lines, 'dependencies');
    final devDepRanges = _collectEntryRanges(lines, 'dev_dependencies');

    final toRemove = <_EntryRange>[];
    final removedDeps = <String>{};
    final removedDevDeps = <String>{};

    for (final name in removeDependencies) {
      final range = depRanges[name];
      if (range != null) {
        toRemove.add(range);
        removedDeps.add(name);
      }
    }
    for (final name in removeDevDependencies) {
      final range = devDepRanges[name];
      if (range != null) {
        toRemove.add(range);
        removedDevDeps.add(name);
      }
    }

    if (toRemove.isEmpty) {
      return const PubspecEditResult(updated: false);
    }

    toRemove.sort((a, b) => b.start.compareTo(a.start));
    for (final range in toRemove) {
      lines.removeRange(range.start, range.end + 1);
    }

    final compacted = _compactExcessBlankLines(lines).join('\n');

    final backupFileName =
        'pubspec_backup_${DateTime.now().millisecondsSinceEpoch}.yaml';
    final backupPath = p.join(backupDirectory, backupFileName);
    await ensureParentDirectory(backupPath);
    await File(backupPath).writeAsString(original);

    await file.writeAsString(compacted);

    try {
      final reparsed = loadYaml(await file.readAsString());
      if (reparsed is! YamlMap) {
        throw const FormatException('pubspec.yaml is not a YAML map');
      }
    } catch (error) {
      await file.writeAsString(original);
      throw StateError('Failed to update pubspec.yaml safely: $error');
    }

    return PubspecEditResult(
      updated: true,
      backupPath: normalizePath(backupPath),
      removedDependencies: removedDeps,
      removedDevDependencies: removedDevDeps,
    );
  }

  Map<String, _EntryRange> _collectEntryRanges(
    List<String> lines,
    String section,
  ) {
    final map = <String, _EntryRange>{};
    final sectionLineRegex = RegExp('^$section\\s*:\\s*\$');
    final topLevelRegex = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_\-]*\s*:\s*$');
    final entryRegex = RegExp(r'^  ([a-zA-Z_][a-zA-Z0-9_\-]*):\s*');

    var sectionStart = -1;
    for (var i = 0; i < lines.length; i++) {
      if (sectionLineRegex.hasMatch(lines[i])) {
        sectionStart = i;
        break;
      }
    }
    if (sectionStart == -1) {
      return map;
    }

    var sectionEnd = lines.length;
    for (var i = sectionStart + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('#') || line.trim().isEmpty) {
        continue;
      }
      if (!line.startsWith(' ') && topLevelRegex.hasMatch(line)) {
        sectionEnd = i;
        break;
      }
    }

    var i = sectionStart + 1;
    while (i < sectionEnd) {
      final line = lines[i];
      final match = entryRegex.firstMatch(line);
      if (match == null) {
        i++;
        continue;
      }

      final name = match.group(1)!;
      var end = i;
      var j = i + 1;
      while (j < sectionEnd) {
        final next = lines[j];
        if (entryRegex.hasMatch(next)) {
          break;
        }
        if (!next.startsWith(' ') && next.trim().isNotEmpty) {
          break;
        }
        end = j;
        j++;
      }

      map[name] = _EntryRange(name: name, start: i, end: end);
      i = j;
    }

    return map;
  }

  List<String> _compactExcessBlankLines(List<String> lines) {
    final output = <String>[];
    var previousBlank = false;
    for (final line in lines) {
      final isBlank = line.trim().isEmpty;
      if (isBlank && previousBlank) {
        continue;
      }
      output.add(line);
      previousBlank = isBlank;
    }
    return output;
  }
}

class _EntryRange {
  const _EntryRange({
    required this.name,
    required this.start,
    required this.end,
  });

  final String name;
  final int start;
  final int end;
}
