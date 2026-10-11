import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_janitor/flutter_janitor.dart';

Future<void> main(List<String> args) async {
  try {
    await run(args);
  } catch (error) {
    stderr.writeln('Cleanup/scan stopped: $error');
    exitCode = 2;
  }
}

Future<void> run(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand('scan', _buildScanParser())
    ..addCommand('clean', _buildCleanParser());

  ArgResults root;
  try {
    root = parser.parse(args);
  } catch (error) {
    stderr.writeln('Argument error: $error');
    _printUsage(parser);
    exitCode = 64;
    return;
  }

  final command = root.command;
  if (command == null || root['help'] == true) {
    _printUsage(parser);
    return;
  }

  if (command['help'] == true) {
    stdout.writeln(parser.commands[command.name]!.usage);
    return;
  }

  final engine = JanitorEngine();
  final writer = ReportWriter();
  final cwd = Directory.current.path;

  if (command.name == 'scan') {
    final options = ScanOptions(
      format: parseReportFormat(command['format'] as String),
      outputPath: command['output'] as String?,
      includeDirs: _parseCsvSet(command['include'] as String),
      excludeDirs: _parseCsvSet(command['exclude'] as String),
      includeNativeScan: command['include-native-scan'] as bool,
    );

    final result = await engine.scan(projectRoot: cwd, options: options);
    final output = writer.renderScan(result, format: options.format);
    await _emitOutput(output, options.outputPath);
    return;
  }

  if (command.name == 'clean') {
    final options = CleanOptions(
      format: parseReportFormat(command['format'] as String),
      outputPath: command['output'] as String?,
      includeDirs: _parseCsvSet(command['include'] as String),
      excludeDirs: _parseCsvSet(command['exclude'] as String),
      includeNativeScan: command['include-native-scan'] as bool,
      apply: command['apply'] as bool,
      interactive: command['interactive'] as bool,
      yes: command['yes'] as bool,
      backupDir: command['backup-dir'] as String?,
      undoManifestPath: command['undo'] as String?,
      runAnalyze: command['run-analyze'] as bool,
      runTests: command['run-tests'] as bool,
      reviewedAssets: (command['remove-asset'] as List<String>).toSet(),
      reviewedDependencies:
          (command['remove-dependency'] as List<String>).toSet(),
      reviewedDevDependencies:
          (command['remove-dev-dependency'] as List<String>).toSet(),
    );

    if (options.undoManifestPath != null &&
        options.undoManifestPath!.trim().isNotEmpty) {
      final restored = await engine.undo(options.undoManifestPath!);
      final output = options.format == ReportFormat.md
          ? '# Flutter Janitor Undo\n\nRestored **$restored** file(s).'
          : 'FLUTTER JANITOR UNDO\nRestored $restored file(s).';
      await _emitOutput(output, options.outputPath);
      return;
    }

    final result = await engine.clean(
      projectRoot: cwd,
      options: options,
      approvalCallback:
          options.interactive ? (plan) => _promptForApproval(plan) : null,
    );

    final output = writer.renderClean(result, format: options.format);
    await _emitOutput(output, options.outputPath);

    if ([...result.preflight, ...result.postflight]
        .any((entry) => !entry.success)) {
      exitCode = 2;
    }
    return;
  }

  _printUsage(parser);
}

ArgParser _buildScanParser() {
  return ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption(
      'format',
      defaultsTo: 'md',
      allowed: const ['md', 'text'],
      help: 'Report output format.',
    )
    ..addOption('output', help: 'Write report to a file path.')
    ..addOption(
      'include',
      defaultsTo: 'test,integration_test,example',
      help: 'Compatibility option; safety scans always cover the full project.',
    )
    ..addOption(
      'exclude',
      defaultsTo: 'build,.dart_tool,ios,android,macos,windows,linux,web',
      help:
          'Compatibility option; cannot narrow the safety scan. Caches are always omitted.',
    )
    ..addFlag(
      'include-native-scan',
      defaultsTo: false,
      help: 'Scan ios/ and android/ for best-effort assets/ string references.',
    );
}

ArgParser _buildCleanParser() {
  return ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addMultiOption('remove-asset',
        splitCommas: false,
        help:
            'Exact unreferenced asset manually reviewed as unused. Repeat for multiple files.')
    ..addMultiOption('remove-dependency',
        splitCommas: false,
        help: 'Exact unreferenced dependency manually reviewed as unused.')
    ..addMultiOption('remove-dev-dependency',
        splitCommas: false,
        help: 'Exact unreferenced dev dependency manually reviewed as unused.')
    ..addFlag('apply', defaultsTo: false, help: 'Apply cleanup changes.')
    ..addFlag(
      'interactive',
      defaultsTo: false,
      help: 'Prompt before applying cleanup changes.',
    )
    ..addFlag(
      'yes',
      defaultsTo: false,
      help: 'Skip confirmation prompt when --apply is set.',
    )
    ..addOption(
      'backup-dir',
      help: 'Backup directory for moved files and manifest.',
    )
    ..addOption('undo', help: 'Restore cleanup from a previous manifest path.')
    ..addFlag(
      'run-analyze',
      defaultsTo: false,
      help: 'Run analyze checks in pre/post flight.',
    )
    ..addFlag(
      'run-tests',
      defaultsTo: false,
      help: 'Run tests in pre/post flight.',
    )
    ..addOption(
      'format',
      defaultsTo: 'md',
      allowed: const ['md', 'text'],
      help: 'Report output format.',
    )
    ..addOption('output', help: 'Write report to a file path.')
    ..addOption(
      'include',
      defaultsTo: 'test,integration_test,example',
      help: 'Compatibility option; safety scans always cover the full project.',
    )
    ..addOption(
      'exclude',
      defaultsTo: 'build,.dart_tool,ios,android,macos,windows,linux,web',
      help:
          'Compatibility option; cannot narrow the safety scan. Caches are always omitted.',
    )
    ..addFlag(
      'include-native-scan',
      defaultsTo: false,
      help: 'Scan ios/ and android/ for best-effort assets/ string references.',
    );
}

Set<String> _parseCsvSet(String value) {
  return value
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toSet();
}

Future<void> _emitOutput(String output, String? outputPath) async {
  if (outputPath == null || outputPath.trim().isEmpty) {
    stdout.writeln(output);
    return;
  }

  final file = File(outputPath);
  if (await FileSystemEntity.type(outputPath, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError(
        'Refusing to overwrite an existing report destination: $outputPath');
  }
  await file.parent.create(recursive: true);
  await file.writeAsString('$output\n');
  stdout.writeln('Report written to $outputPath');
}

Future<bool> _promptForApproval(CleanActionPlan plan) async {
  stdout.writeln('Planned removals:');
  stdout.writeln('- Assets: ${plan.assetPaths.length}');
  stdout.writeln(
    '- Dependencies: ${plan.removeDependencies.length + plan.removeDevDependencies.length}',
  );
  for (final path in plan.assetPaths) {
    stdout.writeln('  asset: $path');
  }
  for (final name in plan.removeDependencies) {
    stdout.writeln('  dependency: $name');
  }
  for (final name in plan.removeDevDependencies) {
    stdout.writeln('  dev dependency: $name');
  }
  stdout.write('Apply these manually reviewed changes? [y/N]: ');
  final response = stdin.readLineSync()?.trim().toLowerCase();
  return response == 'y' || response == 'yes';
}

void _printUsage(ArgParser parser) {
  stdout.writeln('flutter_janitor <command> [arguments]');
  stdout.writeln();
  stdout.writeln('Commands:');
  stdout.writeln('  scan   Scan for unused assets and dependencies.');
  stdout.writeln('  clean  Preview/apply cleanup, or undo via manifest.');
  stdout.writeln();
  stdout.writeln(parser.usage);
}
