import 'dart:collection';

/// Supported output formats for scan/clean reports.
enum ReportFormat {
  /// Markdown report output.
  md,

  /// Plain-text report output.
  text,
}

/// Parses a user-provided report format string.
ReportFormat parseReportFormat(String value) {
  return value.toLowerCase() == 'text' ? ReportFormat.text : ReportFormat.md;
}

/// Returns the CLI label for a [ReportFormat].
String reportFormatLabel(ReportFormat format) {
  return format == ReportFormat.md ? 'md' : 'text';
}

/// Options used by `flutter_janitor scan`.
class ScanOptions {
  /// Creates scan options.
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

  /// Output format used by report writers.
  final ReportFormat format;

  /// Optional output file path.
  final String? outputPath;

  /// Extra directories to include when scanning Dart references.
  final Set<String> includeDirs;

  /// Directories to exclude from scanning.
  final Set<String> excludeDirs;

  /// Whether to include best-effort native asset reference scanning.
  final bool includeNativeScan;
}

/// Options used by `flutter_janitor clean`.
class CleanOptions extends ScanOptions {
  /// Creates clean options.
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

  /// Applies changes when true; otherwise clean runs in dry-run mode.
  final bool apply;

  /// Prompts for confirmation before applying changes.
  final bool interactive;

  /// Skips confirmation prompts.
  final bool yes;

  /// Optional backup directory for moved files and manifests.
  final String? backupDir;

  /// Optional manifest path used to restore previous clean changes.
  final String? undoManifestPath;

  /// Runs analyze as part of pre/post checks.
  final bool runAnalyze;

  /// Runs tests as part of pre/post checks.
  final bool runTests;
}

/// Declared font family data from `pubspec.yaml`.
class DeclaredFontFamily {
  /// Creates a declared font family record.
  const DeclaredFontFamily({required this.family, required this.files});

  /// Family name (for example `AppFont`).
  final String family;

  /// Font files attached to the family.
  final Set<String> files;
}

/// Parsed `pubspec.yaml` data required by janitor analyzers.
class PubspecData {
  /// Creates parsed pubspec data.
  const PubspecData({
    required this.projectRoot,
    required this.pubspecPath,
    required this.declaredAssets,
    required this.fontFamilies,
    required this.dependencies,
    required this.devDependencies,
  });

  /// Absolute project root path.
  final String projectRoot;

  /// Absolute `pubspec.yaml` path.
  final String pubspecPath;

  /// Expanded set of declared asset file paths.
  final Set<String> declaredAssets;

  /// Font families keyed by family name.
  final Map<String, DeclaredFontFamily> fontFamilies;

  /// `dependencies` section from pubspec.
  final Map<String, String> dependencies;

  /// `dev_dependencies` section from pubspec.
  final Map<String, String> devDependencies;

  /// Returns dependencies and dev dependencies merged into one map.
  Map<String, String> allDependencies() {
    return {...dependencies, ...devDependencies};
  }
}

/// References discovered while scanning Dart/native sources.
class DartReferenceScanResult {
  /// Creates an empty or seeded reference result.
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

  /// Asset file paths detected as used.
  final Set<String> usedAssets;

  /// Prefixes that indicate dynamic/unsafe asset usage patterns.
  final Set<String> unsafeAssetPrefixes;

  /// Font families detected from code usage.
  final Set<String> usedFontFamilies;

  /// Packages detected from `import`/`export package:` directives.
  final Set<String> usedPackages;

  /// Package names detected but not resolved confidently.
  final Set<String> importedUnknownPackages;

  /// Merges another reference result into this one.
  void merge(DartReferenceScanResult other) {
    usedAssets.addAll(other.usedAssets);
    unsafeAssetPrefixes.addAll(other.unsafeAssetPrefixes);
    usedFontFamilies.addAll(other.usedFontFamilies);
    usedPackages.addAll(other.usedPackages);
    importedUnknownPackages.addAll(other.importedUnknownPackages);
  }
}

/// Asset classification result.
class AssetAnalysis {
  /// Creates an asset analysis result.
  const AssetAnalysis({
    required this.used,
    required this.unusedSafe,
    required this.unusedUnsafe,
    required this.missingReferences,
    required this.unsafePrefixes,
  });

  /// Declared assets known to be used.
  final Set<String> used;

  /// Declared assets safe to remove automatically.
  final Set<String> unusedSafe;

  /// Declared assets potentially unused but unsafe to auto-remove.
  final Set<String> unusedUnsafe;

  /// Assets referenced in code but not declared in pubspec.
  final Set<String> missingReferences;

  /// Unsafe prefixes that caused unsafe classification.
  final Set<String> unsafePrefixes;
}

/// Dependency classification result.
class DependencyAnalysis {
  /// Creates a dependency analysis result.
  const DependencyAnalysis({
    required this.used,
    required this.unusedSafe,
    required this.unusedUnsafe,
    required this.unsafeReasons,
    required this.protected,
  });

  /// Dependencies confirmed as used.
  final Set<String> used;

  /// Dependencies safe to remove automatically.
  final Set<String> unusedSafe;

  /// Dependencies potentially unused but unsafe to auto-remove.
  final Set<String> unusedUnsafe;

  /// Unsafe dependency reasons keyed by dependency name.
  final Map<String, String> unsafeReasons;

  /// Dependencies that are intentionally protected.
  final Set<String> protected;
}

/// Full scan output for a project.
class JanitorScanResult {
  /// Creates a scan result.
  const JanitorScanResult({
    required this.projectRoot,
    required this.pubspec,
    required this.assetAnalysis,
    required this.dependencyAnalysis,
    required this.toolingHits,
  });

  /// Absolute project root path.
  final String projectRoot;

  /// Parsed pubspec data used in this scan.
  final PubspecData pubspec;

  /// Asset analysis output.
  final AssetAnalysis assetAnalysis;

  /// Dependency analysis output.
  final DependencyAnalysis dependencyAnalysis;

  /// Tooling/config file mentions keyed by package name.
  final Map<String, Set<String>> toolingHits;

  /// Total number of declared assets.
  int get declaredAssetCount => pubspec.declaredAssets.length;

  /// Total number of declared dependencies and dev dependencies.
  int get declaredDependencyCount =>
      pubspec.dependencies.length + pubspec.devDependencies.length;
}

/// Result of running an external command.
class RunResult {
  /// Creates a command run result.
  const RunResult({
    required this.success,
    required this.command,
    this.output = '',
  });

  /// Whether the command completed successfully.
  final bool success;

  /// String representation of the executed command.
  final String command;

  /// Combined stdout/stderr output.
  final String output;
}

/// Set of changes that clean can apply.
class CleanActionPlan {
  /// Creates a clean action plan.
  const CleanActionPlan({
    required this.assetPaths,
    required this.removeDependencies,
    required this.removeDevDependencies,
  });

  /// Asset paths eligible for removal.
  final Set<String> assetPaths;

  /// Dependency names to remove from `dependencies`.
  final Set<String> removeDependencies;

  /// Dependency names to remove from `dev_dependencies`.
  final Set<String> removeDevDependencies;

  /// Returns true when there is at least one change to apply.
  bool get hasChanges =>
      assetPaths.isNotEmpty ||
      removeDependencies.isNotEmpty ||
      removeDevDependencies.isNotEmpty;
}

/// Mapping of one moved file during clean.
class CleanManifestEntry {
  /// Creates a moved-file entry.
  const CleanManifestEntry({
    required this.originalPath,
    required this.backupPath,
  });

  /// Original absolute file path before clean.
  final String originalPath;

  /// Backup absolute file path after clean.
  final String backupPath;
}

/// Manifest containing clean backup/restore information.
class CleanManifest {
  /// Creates a clean manifest.
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

  /// Manifest timestamp.
  final DateTime timestamp;

  /// Project root this manifest belongs to.
  final String projectRoot;

  /// Manifest file path.
  final String manifestPath;

  /// Files moved during clean.
  final List<CleanManifestEntry> movedFiles;

  /// Backed up pubspec path if pubspec was edited.
  final String? pubspecBackupPath;

  /// Removed dependency names.
  final Set<String> removedDependencies;

  /// Removed dev dependency names.
  final Set<String> removedDevDependencies;
}

/// Output from a clean run.
class CleanExecutionResult {
  /// Creates a clean execution result.
  const CleanExecutionResult({
    required this.scanResult,
    required this.plan,
    required this.applied,
    this.manifest,
    this.preflight = const [],
    this.postflight = const [],
    this.messages = const [],
  });

  /// Scan result used to generate this clean run.
  final JanitorScanResult scanResult;

  /// Applied/preview action plan.
  final CleanActionPlan plan;

  /// Whether changes were applied.
  final bool applied;

  /// Manifest generated when changes were applied.
  final CleanManifest? manifest;

  /// Preflight command results.
  final List<RunResult> preflight;

  /// Postflight command results.
  final List<RunResult> postflight;

  /// Human-readable clean notes.
  final List<String> messages;
}
