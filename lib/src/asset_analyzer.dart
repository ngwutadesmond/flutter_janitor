import 'package:path/path.dart' as p;
import 'models.dart';
import 'path_utils.dart';
import 'pubspec_parser.dart';

class AssetAnalyzer {
  AssetAnalysis analyze(
      {required PubspecData pubspec,
      required DartReferenceScanResult references}) {
    final used = <String>{...references.usedAssets.map(normalizePath)};
    // Declarations of fonts and configured assets are themselves meaningful use.
    for (final family in pubspec.fontFamilies.values) {
      used.addAll(family.files);
    }
    for (final entry in pubspec.assetReasons.entries) {
      if (entry.value.startsWith('Configured asset')) used.add(entry.key);
    }
    final declared = pubspec.declaredAssets;
    for (final asset in declared) {
      final dir = p.dirname(asset);
      if (PubspecParser.variantDirectory.hasMatch(p.basename(dir))) {
        final base = normalizePath(p.join(p.dirname(dir), p.basename(asset)));
        if (used.contains(base)) used.add(asset);
      }
    }
    final reasons = <String, String>{};
    for (final asset in declared.difference(used)) {
      reasons[asset] = pubspec.assetReasons[asset] ??
          'No reference found; external, generated or runtime use is not ruled out. Review before selecting.';
      if (references.warnings.isNotEmpty) {
        reasons[asset] =
            '${reasons[asset]} ${references.warnings.toList()..sort()}';
      }
    }
    return AssetAnalysis(
        used: used,
        unusedSafe: {},
        unusedUnsafe: reasons.keys.toSet(),
        missingReferences: used
            .difference(declared)
            .where((x) => !x.startsWith('packages/'))
            .toSet(),
        unsafePrefixes: references.unsafeAssetPrefixes,
        unsafeReasons: reasons);
  }
}
