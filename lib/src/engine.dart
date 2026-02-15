import 'package:path/path.dart' as p;

import 'asset_analyzer.dart';
import 'cleaner.dart';
import 'dart_reference_scanner.dart';
import 'dependency_analyzer.dart';
import 'models.dart';
import 'native_reference_scanner.dart';
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
    final normalizedRoot = p.normalize(projectRoot);
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
    if (options.undoManifestPath != null &&
        options.undoManifestPath!.trim().isNotEmpty) {
      final restored = await _cleaner.undo(
        manifestPath: options.undoManifestPath!,
      );
      final emptyScan = await scan(projectRoot: projectRoot, options: options);
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

    final scanResult = await scan(projectRoot: projectRoot, options: options);
    final plan = CleanActionPlan(
      assetPaths: scanResult.assetAnalysis.unusedSafe,
      removeDependencies: scanResult.dependencyAnalysis.unusedSafe
          .where((entry) => scanResult.pubspec.dependencies.containsKey(entry))
          .toSet(),
      removeDevDependencies: scanResult.dependencyAnalysis.unusedSafe
          .where(
            (entry) => scanResult.pubspec.devDependencies.containsKey(entry),
          )
          .toSet(),
    );

    if (!options.apply || !plan.hasChanges) {
      final messages = <String>[];
      if (!options.apply) {
        messages.add(
          'Dry run only. Use --apply to move files and edit pubspec.yaml.',
        );
      }
      if (!plan.hasChanges) {
        messages.add('No safe cleanup candidates found.');
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
    if (!approved && !options.interactive && !options.yes) {
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
      projectRoot: projectRoot,
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

    final backupDir = options.backupDir ?? '.janitor_backup';
    final manifest = await _cleaner.apply(
      projectRoot: projectRoot,
      plan: plan,
      backupDir: backupDir,
    );

    final postflight = await _healthCheckRunner.runChecks(
      projectRoot: projectRoot,
      runAnalyze: options.runAnalyze,
      runTests: options.runTests,
    );

    final messages = <String>[];
    if (postflight.any((entry) => !entry.success)) {
      messages.add(
        'Postflight check failed. Use `flutter_janitor clean --undo ${manifest.manifestPath}` to restore.',
      );
    }

    return CleanExecutionResult(
      scanResult: scanResult,
      plan: plan,
      applied: true,
      manifest: manifest,
      preflight: preflight,
      postflight: postflight,
      messages: messages,
    );
  }

  /// Restores a previously applied clean operation from a manifest.
  Future<int> undo(String manifestPath) {
    return _cleaner.undo(manifestPath: manifestPath);
  }
}
