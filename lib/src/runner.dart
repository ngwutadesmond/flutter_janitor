import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'models.dart';
import 'project_walker.dart';

abstract class CommandExecutor {
  Future<RunResult> run(String executable, List<String> arguments,
      {required String workingDirectory});
  Future<bool> commandExists(String executable);
}

class ProcessCommandExecutor implements CommandExecutor {
  @override
  Future<bool> commandExists(String executable) async {
    final extensions = Platform.isWindows ? ['', '.exe', '.bat', '.cmd'] : [''];
    for (final directory in (Platform.environment['PATH'] ?? '')
        .split(Platform.isWindows ? ';' : ':')) {
      for (final extension in extensions) {
        if (File(p.join(directory, '$executable$extension')).existsSync()) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Future<RunResult> run(String executable, List<String> arguments,
      {required String workingDirectory}) async {
    final command = '$executable ${arguments.join(' ')}';
    try {
      final result = await Process.run(executable, arguments,
          workingDirectory: workingDirectory, runInShell: Platform.isWindows);
      return RunResult(
          success: result.exitCode == 0,
          command: command,
          output: '${result.stdout}\n${result.stderr}'.trim());
    } on ProcessException catch (error) {
      return RunResult(success: false, command: command, output: '$error');
    }
  }
}

/// Optional checks run in a disposable project copy. Plain cleanup never runs
/// pub get or modifies the consumer's lockfile/package configuration.
class HealthCheckRunner {
  HealthCheckRunner({CommandExecutor? executor})
      : _executor = executor ?? ProcessCommandExecutor();
  final CommandExecutor _executor;
  Future<List<RunResult>> runChecks(
      {required String projectRoot,
      required bool runAnalyze,
      required bool runTests}) async {
    if (!runAnalyze && !runTests) return [];
    final yaml =
        loadYaml(await File(p.join(projectRoot, 'pubspec.yaml')).readAsString())
            as YamlMap;
    final deps = yaml['dependencies'];
    final command = yaml.containsKey('flutter') ||
            (deps is YamlMap && deps.containsKey('flutter'))
        ? 'flutter'
        : 'dart';
    if (!await _executor.commandExists(command)) {
      return [
        RunResult(
            success: false,
            command: command,
            output: 'Required SDK is unavailable.')
      ];
    }
    final copy = await Directory.systemTemp.createTemp('janitor-check-');
    try {
      final warnings = <String>{};
      final files =
          await ProjectWalker(projectRoot: projectRoot, excludeRoots: {})
              .listProjectFiles(warnings: warnings);
      if (warnings.isNotEmpty) {
        return [
          RunResult(
              success: false, command: 'copy', output: warnings.join('\n'))
        ];
      }
      for (final relative in files) {
        final target = File(p.join(copy.path, relative));
        await target.parent.create(recursive: true);
        await File(p.join(projectRoot, relative)).copy(target.path);
      }
      final results = <RunResult>[];
      for (final args in [
        ['pub', 'get'],
        if (runAnalyze) ['analyze'],
        if (runTests) ['test']
      ]) {
        final result =
            await _executor.run(command, args, workingDirectory: copy.path);
        results.add(result);
        if (!result.success) break;
      }
      return results;
    } finally {
      await copy.delete(recursive: true);
    }
  }
}
