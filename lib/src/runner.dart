import 'dart:async';
import 'dart:io';

import 'models.dart';

abstract class CommandExecutor {
  Future<RunResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  });

  Future<bool> commandExists(String executable);
}

class ProcessCommandExecutor implements CommandExecutor {
  @override
  Future<bool> commandExists(String executable) async {
    final result = await Process.run('which', [executable]);
    return result.exitCode == 0;
  }

  @override
  Future<RunResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    final processResult = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    final command = '$executable ${arguments.join(' ')}'.trim();
    final output = '${processResult.stdout}\n${processResult.stderr}'.trim();
    return RunResult(
      success: processResult.exitCode == 0,
      command: command,
      output: output,
    );
  }
}

class HealthCheckRunner {
  HealthCheckRunner({CommandExecutor? executor})
      : _executor = executor ?? ProcessCommandExecutor();

  final CommandExecutor _executor;

  Future<List<RunResult>> runChecks({
    required String projectRoot,
    required bool runAnalyze,
    required bool runTests,
  }) async {
    final results = <RunResult>[];

    results.add(
      await _executor.run(
          'dart',
          [
            'pub',
            'get',
          ],
          workingDirectory: projectRoot),
    );

    if (await _executor.commandExists('flutter')) {
      results.add(
        await _executor.run(
            'flutter',
            [
              'pub',
              'get',
            ],
            workingDirectory: projectRoot),
      );
    }

    if (runAnalyze) {
      if (await _executor.commandExists('flutter')) {
        results.add(
          await _executor.run(
              'flutter',
              [
                'analyze',
              ],
              workingDirectory: projectRoot),
        );
      } else {
        results.add(
          await _executor.run(
              'dart',
              [
                'analyze',
              ],
              workingDirectory: projectRoot),
        );
      }
    }

    if (runTests) {
      if (await _executor.commandExists('flutter')) {
        results.add(
          await _executor.run(
              'flutter',
              [
                'test',
              ],
              workingDirectory: projectRoot),
        );
      } else {
        results.add(
          await _executor.run('dart', ['test'], workingDirectory: projectRoot),
        );
      }
    }

    return results;
  }
}
