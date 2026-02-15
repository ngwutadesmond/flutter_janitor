import 'models.dart';

class DependencyAnalyzer {
  static const Set<String> protectedDependencies = {
    'flutter',
    'flutter_test',
    'cupertino_icons',
  };

  DependencyAnalysis analyze({
    required PubspecData pubspec,
    required DartReferenceScanResult references,
    required Map<String, Set<String>> toolingHits,
  }) {
    final used = <String>{};
    final unusedSafe = <String>{};
    final unusedUnsafe = <String>{};
    final unsafeReasons = <String, String>{};
    final protected = <String>{};

    final allDependencies = pubspec.allDependencies();
    final usedPackages = references.usedPackages;
    final normalizedUsed = usedPackages.map(_canonicalize).toSet();

    for (final packageName in allDependencies.keys) {
      if (protectedDependencies.contains(packageName)) {
        protected.add(packageName);
        continue;
      }

      if (usedPackages.contains(packageName)) {
        used.add(packageName);
        continue;
      }

      final tooling = toolingHits[packageName];
      if (tooling != null && tooling.isNotEmpty) {
        unusedUnsafe.add(packageName);
        unsafeReasons[packageName] =
            'Referenced in tooling/config files (${tooling.length} hit${tooling.length == 1 ? '' : 's'}).';
        continue;
      }

      final canonical = _canonicalize(packageName);
      if (normalizedUsed.contains(canonical)) {
        unusedUnsafe.add(packageName);
        unsafeReasons[packageName] =
            'Import/package name mismatch detected; verify manually.';
        continue;
      }

      unusedSafe.add(packageName);
    }

    return DependencyAnalysis(
      used: used,
      unusedSafe: unusedSafe,
      unusedUnsafe: unusedUnsafe,
      unsafeReasons: unsafeReasons,
      protected: protected,
    );
  }

  String _canonicalize(String name) {
    return name.replaceAll('_', '').toLowerCase();
  }
}
