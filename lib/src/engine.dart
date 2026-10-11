import 'dart:io';

import 'asset_analyzer.dart';
import 'cleaner.dart';
import 'dart_reference_scanner.dart';
import 'dependency_analyzer.dart';
import 'models.dart';
import 'native_reference_scanner.dart';
import 'path_utils.dart';
import 'project_walker.dart';
import 'pubspec_parser.dart';
import 'runner.dart';
import 'tooling_scanner.dart';

/// High-level orchestrator for scan/clean/undo operations.
class JanitorEngine {
  /// Creates a janitor engine with optional custom dependencies.
  JanitorEngine({
    PubspecParser? pubspecParser,
    DartReferenceScanner? dartReferenceScanner,
    NativeReferenceScanner? nativeReferenceScanner,
    AssetAnalyzer? assetAnalyzer,
    DependencyAnalyzer? dependencyAnalyzer,
    ToolingScanner? toolingScanner,
    Cleaner? cleaner,
    HealthCheckRunner? healthCheckRunner,
  })  : _pubspecParser = pubspecParser ?? PubspecParser(),
        _dartReferenceScanner = dartReferenceScanner ?? DartReferenceScanner(),
        _nativeReferenceScanner =
            nativeReferenceScanner ?? NativeReferenceScanner(),
        _assetAnalyzer = assetAnalyzer ?? AssetAnalyzer(),
        _dependencyAnalyzer = dependencyAnalyzer ?? DependencyAnalyzer(),
        _toolingScanner = toolingScanner ?? ToolingScanner(),
        _cleaner = cleaner ?? Cleaner(),
        _healthCheckRunner = healthCheckRunner ?? HealthCheckRunner();

  final PubspecParser _pubspecParser;
  final DartReferenceScanner _dartReferenceScanner;
  final NativeReferenceScanner _nativeReferenceScanner;
  final AssetAnalyzer _assetAnalyzer;
  final DependencyAnalyzer _dependencyAnalyzer;
  final ToolingScanner _toolingScanner;
  final Cleaner _cleaner;
  final HealthCheckRunner _healthCheckRunner;

  /// Scans a project and returns asset/dependency analysis results.
  Future<JanitorScanResult> scan({
    required String projectRoot,
    ScanOptions options = const ScanOptions(),
  }) async {
    final normalizedRoot = checkedRoot(projectRoot);
    final pubspec = await _pubspecParser.parse(normalizedRoot);
    final walker = ProjectWalker(
      projectRoot: normalizedRoot,
      excludeRoots: options.excludeDirs,
    );

    final dartFiles = await walker.listDartFiles(
      includeRoots: options.includeDirs,
    );
    final references = await _dartReferenceScanner.scanFiles(
      projectRoot: normalizedRoot,
      dartFiles: dartFiles,
    );

    if (options.includeNativeScan) {
      final nativeReferences = await _nativeReferenceScanner.scan(
        projectRoot: normalizedRoot,
      );
      references.merge(nativeReferences);
    }

    final toolingHits = await _toolingScanner.scanToolingMentions(
      projectRoot: normalizedRoot,
      packageNames: pubspec.allDependencies().keys,
      references: references,
      assets: pubspec.declaredAssets,
    );

    final assetAnalysis = _assetAnalyzer.analyze(
      pubspec: pubspec,
      references: references,
    );
    final dependencyAnalysis = _dependencyAnalyzer.analyze(
      pubspec: pubspec,
      references: references,
      toolingHits: toolingHits,
    );

    return JanitorScanResult(
      projectRoot: normalizedRoot,
      pubspec: pubspec,
      assetAnalysis: assetAnalysis,
      dependencyAnalysis: dependencyAnalysis,
      toolingHits: toolingHits,
    );
  }

  /// Runs clean in dry-run or apply mode, and supports undo via manifest.
  Future<CleanExecutionResult> clean({
    required String projectRoot,
    CleanOptions options = const CleanOptions(),
    Future<bool> Function(CleanActionPlan plan)? approvalCallback,
  }) async {
    final root = checkedRoot(projectRoot);
    if (options.undoManifestPath != null &&
        options.undoManifestPath!.trim().isNotEmpty) {
      final restored = await _cleaner.undo(
        manifestPath: options.undoManifestPath!,
        projectRoot: root,
      );
      final emptyScan = await scan(projectRoot: root, options: options);
      return CleanExecutionResult(
        scanResult: emptyScan,
        plan: const CleanActionPlan(
          assetPaths: <String>{},
          removeDependencies: <String>{},
          removeDevDependencies: <String>{},
        ),
        applied: false,
        messages: ['Undo completed. Restored $restored files.'],
      );
    }

    final scanResult = await scan(projectRoot: root, options: options);
    if (scanResult.pubspec.reportOnlyReasons.isNotEmpty && options.apply) {
      throw StateError(scanResult.pubspec.reportOnlyReasons.join(' '));
    }
    void requireCandidates(
        Set<String> selection, Set<String> candidates, String kind) {
      final invalid = selection.difference(candidates);
      if (invalid.isNotEmpty) {
        throw StateError(
            'Cannot remove used, protected or undeclared $kind: $invalid');
      }
    }

    requireCandidates(options.reviewedAssets,
        scanResult.assetAnalysis.unusedUnsafe, 'assets');
    for (final asset in options.reviewedAssets) {
      if (scanResult.pubspec.assetReasons.containsKey(asset)) {
        throw StateError(
            'Protected asset requires manual group-level changes: $asset');
      }
    }
    requireCandidates(
        options.reviewedDependencies,
        scanResult.dependencyAnalysis.unusedUnsafe
            .intersection(scanResult.pubspec.dependencies.keys.toSet()),
        'dependencies');
    requireCandidates(
        options.reviewedDevDependencies,
        scanResult.dependencyAnalysis.unusedUnsafe
            .intersection(scanResult.pubspec.devDependencies.keys.toSet()),
        'dev dependencies');
    // Tooling/config evidence is positive usage, not a removal candidate.
    for (final dependency in {
      ...options.reviewedDependencies,
      ...options.reviewedDevDependencies
    }) {
      if (scanResult.toolingHits[dependency]?.isNotEmpty ?? false) {
        throw StateError(
            'Dependency is referenced by project tooling/config: $dependency');
      }
    }
    final plan = CleanActionPlan(
      assetPaths: options.reviewedAssets,
      removeDependencies: options.reviewedDependencies,
      removeDevDependencies: options.reviewedDevDependencies,
    );

    if (!options.apply || !plan.hasChanges) {
      final messages = <String>[];
      if (!options.apply) {
        messages.add(
          'Dry run only. Use --apply to move files and edit pubspec.yaml.',
        );
      }
      if (!plan.hasChanges) {
        messages.add(
            'No reviewed items selected. Unknown usage is never removed automatically. Use explicit --remove-asset/--remove-dependency/--remove-dev-dependency after manual review.');
      }
      return CleanExecutionResult(
        scanResult: scanResult,
        plan: plan,
        applied: false,
        messages: messages,
      );
    }

    var approved = options.yes;
    if (!approved && approvalCallback != null) {
      approved = await approvalCallback(plan);
    }
    if (!approved) {
      return CleanExecutionResult(
        scanResult: scanResult,
        plan: plan,
        applied: false,
        messages: [
          'Apply requested without confirmation. Use --yes or --interactive.',
        ],
      );
    }

    final preflight = await _healthCheckRunner.runChecks(
      projectRoot: root,
      runAnalyze: options.runAnalyze,
      runTests: options.runTests,
    );
    if (preflight.any((entry) => !entry.success)) {
      return CleanExecutionResult(
        scanResult: scanResult,
        plan: plan,
        applied: false,
        preflight: preflight,
        messages: ['Preflight checks failed. Cleanup aborted.'],
      );
    }

    // Confirmation/checks can take time. Re-scan and ensure selected items have
    // not acquired positive usage before invoking the transaction.
    final current = await scan(projectRoot: root, options: options);
    requireCandidates(
        plan.assetPaths, current.assetAnalysis.unusedUnsafe, 'assets');
    requireCandidates(
        {...plan.removeDependencies, ...plan.removeDevDependencies},
        current.dependencyAnalysis.unusedUnsafe,
        'dependencies');
    for (final dependency in {
      ...plan.removeDependencies,
      ...plan.removeDevDependencies
    }) {
      if (current.toolingHits[dependency]?.isNotEmpty ?? false) {
        throw StateError('New tooling reference: $dependency');
      }
    }
    final backupDir = options.backupDir ?? '.janitor_backup';
    final manifest = await _cleaner.apply(
      projectRoot: root,
      plan: plan,
      backupDir: backupDir,
    );

    List<RunResult> postflight;
    try {
      postflight = await _healthCheckRunner.runChecks(
          projectRoot: root,
          runAnalyze: options.runAnalyze,
          runTests: options.runTests);
    } catch (error) {
      postflight = [
        RunResult(success: false, command: 'postflight', output: '$error')
      ];
    }

    final messages = <String>[];
    if (postflight.any((entry) => !entry.success)) {
      await _cleaner.undo(
          manifestPath: manifest.manifestPath, projectRoot: root);
      messages.add(
          'Postflight checks failed. Cleanup was rolled back. Journal: ${manifest.manifestPath}');
    }

    return CleanExecutionResult(
      scanResult: scanResult,
      plan: plan,
      applied: !postflight.any((entry) => !entry.success),
      manifest: manifest,
      preflight: preflight,
      postflight: postflight,
      messages: messages,
    );
  }

  /// Restores a previously applied clean operation from a manifest.
  Future<int> undo(String manifestPath, {String? projectRoot}) {
    return _cleaner.undo(
        manifestPath: manifestPath,
        projectRoot: projectRoot ?? Directory.current.path);
  }
}
