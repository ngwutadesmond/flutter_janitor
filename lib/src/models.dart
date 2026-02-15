import 'dart:collection';

enum ReportFormat { md, text }

ReportFormat parseReportFormat(String value) {
  return value.toLowerCase() == 'text' ? ReportFormat.text : ReportFormat.md;
}

String reportFormatLabel(ReportFormat format) {
  return format == ReportFormat.md ? 'md' : 'text';
}

class ScanOptions {
  const ScanOptions({
    this.format = ReportFormat.md,
    this.outputPath,
    this.includeDirs = const {'test', 'integration_test', 'example'},
    this.excludeDirs = const {
      'build',
      '.dart_tool',
      'ios',
      'android',
      'macos',
      'windows',
      'linux',
      'web',
    },
    this.includeNativeScan = false,
  });

  final ReportFormat format;
  final String? outputPath;
  final Set<String> includeDirs;
  final Set<String> excludeDirs;
  final bool includeNativeScan;
}

class CleanOptions extends ScanOptions {
  const CleanOptions({
    super.format = ReportFormat.md,
    super.outputPath,
    super.includeDirs,
    super.excludeDirs,
    super.includeNativeScan,
    this.apply = false,
    this.interactive = false,
    this.yes = false,
    this.backupDir,
    this.undoManifestPath,
    this.runAnalyze = false,
    this.runTests = false,
  });

  final bool apply;
  final bool interactive;
  final bool yes;
  final String? backupDir;
  final String? undoManifestPath;
  final bool runAnalyze;
  final bool runTests;
}

class DeclaredFontFamily {
  const DeclaredFontFamily({required this.family, required this.files});

  final String family;
  final Set<String> files;
}

class PubspecData {
  const PubspecData({
    required this.projectRoot,
    required this.pubspecPath,
    required this.declaredAssets,
    required this.fontFamilies,
    required this.dependencies,
    required this.devDependencies,
  });

  final String projectRoot;
  final String pubspecPath;
  final Set<String> declaredAssets;
  final Map<String, DeclaredFontFamily> fontFamilies;
  final Map<String, String> dependencies;
  final Map<String, String> devDependencies;

  Map<String, String> allDependencies() {
    return {...dependencies, ...devDependencies};
  }
}

class DartReferenceScanResult {
  DartReferenceScanResult({
    Set<String>? usedAssets,
    Set<String>? unsafeAssetPrefixes,
    Set<String>? usedFontFamilies,
    Set<String>? usedPackages,
    Set<String>? importedUnknownPackages,
  })  : usedAssets = usedAssets ?? <String>{},
        unsafeAssetPrefixes = unsafeAssetPrefixes ?? <String>{},
        usedFontFamilies = usedFontFamilies ?? <String>{},
        usedPackages = usedPackages ?? <String>{},
        importedUnknownPackages = importedUnknownPackages ?? <String>{};

  final Set<String> usedAssets;
  final Set<String> unsafeAssetPrefixes;
  final Set<String> usedFontFamilies;
  final Set<String> usedPackages;
  final Set<String> importedUnknownPackages;

  void merge(DartReferenceScanResult other) {
    usedAssets.addAll(other.usedAssets);
    unsafeAssetPrefixes.addAll(other.unsafeAssetPrefixes);
    usedFontFamilies.addAll(other.usedFontFamilies);
    usedPackages.addAll(other.usedPackages);
    importedUnknownPackages.addAll(other.importedUnknownPackages);
  }
}

class AssetAnalysis {
  const AssetAnalysis({
    required this.used,
    required this.unusedSafe,
    required this.unusedUnsafe,
    required this.missingReferences,
    required this.unsafePrefixes,
  });

  final Set<String> used;
  final Set<String> unusedSafe;
  final Set<String> unusedUnsafe;
  final Set<String> missingReferences;
  final Set<String> unsafePrefixes;
}

class DependencyAnalysis {
  const DependencyAnalysis({
    required this.used,
    required this.unusedSafe,
    required this.unusedUnsafe,
    required this.unsafeReasons,
    required this.protected,
  });

  final Set<String> used;
  final Set<String> unusedSafe;
  final Set<String> unusedUnsafe;
  final Map<String, String> unsafeReasons;
  final Set<String> protected;
}

class JanitorScanResult {
  const JanitorScanResult({
    required this.projectRoot,
    required this.pubspec,
    required this.assetAnalysis,
    required this.dependencyAnalysis,
    required this.toolingHits,
  });

  final String projectRoot;
  final PubspecData pubspec;
  final AssetAnalysis assetAnalysis;
  final DependencyAnalysis dependencyAnalysis;
  final Map<String, Set<String>> toolingHits;

  int get declaredAssetCount => pubspec.declaredAssets.length;
  int get declaredDependencyCount =>
      pubspec.dependencies.length + pubspec.devDependencies.length;
}

class RunResult {
  const RunResult({
    required this.success,
    required this.command,
    this.output = '',
  });

  final bool success;
  final String command;
  final String output;
}

class CleanActionPlan {
  const CleanActionPlan({
    required this.assetPaths,
    required this.removeDependencies,
    required this.removeDevDependencies,
  });

  final Set<String> assetPaths;
  final Set<String> removeDependencies;
  final Set<String> removeDevDependencies;

  bool get hasChanges =>
      assetPaths.isNotEmpty ||
      removeDependencies.isNotEmpty ||
      removeDevDependencies.isNotEmpty;
}

class CleanManifestEntry {
  const CleanManifestEntry({
    required this.originalPath,
    required this.backupPath,
  });

  final String originalPath;
  final String backupPath;
}

class CleanManifest {
  CleanManifest({
    required this.timestamp,
    required this.projectRoot,
    required this.manifestPath,
    List<CleanManifestEntry>? movedFiles,
    this.pubspecBackupPath,
    Set<String>? removedDependencies,
    Set<String>? removedDevDependencies,
  })  : movedFiles = List<CleanManifestEntry>.from(movedFiles ?? const []),
        removedDependencies = LinkedHashSet<String>.from(
          removedDependencies ?? const <String>{},
        ),
        removedDevDependencies = LinkedHashSet<String>.from(
          removedDevDependencies ?? const <String>{},
        );

  final DateTime timestamp;
  final String projectRoot;
  final String manifestPath;
  final List<CleanManifestEntry> movedFiles;
  final String? pubspecBackupPath;
  final Set<String> removedDependencies;
  final Set<String> removedDevDependencies;
}

class CleanExecutionResult {
  const CleanExecutionResult({
    required this.scanResult,
    required this.plan,
    required this.applied,
    this.manifest,
    this.preflight = const [],
    this.postflight = const [],
    this.messages = const [],
  });

  final JanitorScanResult scanResult;
  final CleanActionPlan plan;
  final bool applied;
  final CleanManifest? manifest;
  final List<RunResult> preflight;
  final List<RunResult> postflight;
  final List<String> messages;
}
