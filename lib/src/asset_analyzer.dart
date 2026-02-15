import 'models.dart';
import 'path_utils.dart';

class AssetAnalyzer {
  AssetAnalysis analyze({
    required PubspecData pubspec,
    required DartReferenceScanResult references,
  }) {
    final used = <String>{...references.usedAssets.map(normalizePath)};

    for (final entry in pubspec.fontFamilies.entries) {
      final familyName = entry.key;
      if (references.usedFontFamilies.contains(familyName)) {
        used.addAll(entry.value.files.map(normalizePath));
      }
    }

    final declared = pubspec.declaredAssets.map(normalizePath).toSet();
    final unsafePrefixes =
        references.unsafeAssetPrefixes.map(ensureTrailingSlash).toSet();

    final unusedSafe = <String>{};
    final unusedUnsafe = <String>{};

    for (final asset in declared) {
      if (used.contains(asset)) {
        continue;
      }
      final isUnsafe = unsafePrefixes.any(
        (prefix) => asset == prefix || asset.startsWith(prefix),
      );
      if (isUnsafe) {
        unusedUnsafe.add(asset);
      } else {
        unusedSafe.add(asset);
      }
    }

    final missingReferences = <String>{};
    for (final reference in used) {
      if (!declared.contains(reference)) {
        missingReferences.add(reference);
      }
    }

    return AssetAnalysis(
      used: used,
      unusedSafe: unusedSafe,
      unusedUnsafe: unusedUnsafe,
      missingReferences: missingReferences,
      unsafePrefixes: unsafePrefixes,
    );
  }
}
