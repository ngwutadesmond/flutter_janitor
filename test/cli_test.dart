import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'safety_test.dart' as fixture;

void main() {
  final executable = p.join(p.dirname(Platform.resolvedExecutable),
      'dart${Platform.isWindows ? '.exe' : ''}');
  final packages = p.absolute('.dart_tool/package_config.json');
  final cli = p.absolute('bin/flutter_janitor.dart');
  Future<ProcessResult> run(Directory root, List<String> args) =>
      Process.run(executable, ['--packages=$packages', cli, ...args],
          workingDirectory: root.path);
  test('CLI dry run, explicit apply, manifest consistency and repeat undo',
      () async {
    final root = await fixture.project();
    final original = File('${root.path}/pubspec.yaml').readAsBytesSync();
    final scan =
        await run(root, ['scan', '--format', 'text', '--include-native-scan']);
    expect(scan.exitCode, 0, reason: '${scan.stderr}');
    expect(scan.stdout, contains('No unknown items are removed automatically'));
    final dry = await run(root, [
      'clean',
      '--remove-asset',
      'explicit.png',
      '--remove-dependency',
      'unused'
    ]);
    expect(dry.exitCode, 0, reason: '${dry.stderr}');
    expect(File('${root.path}/pubspec.yaml').readAsBytesSync(), original);
    final applied = await run(root, [
      'clean',
      '--remove-asset',
      'explicit.png',
      '--remove-dependency',
      'unused',
      '--apply',
      '--yes'
    ]);
    expect(applied.exitCode, 0, reason: '${applied.stderr}');
    expect(File('${root.path}/explicit.png').existsSync(), false);
    final yaml = loadYaml(File('${root.path}/pubspec.yaml').readAsStringSync());
    expect(yaml['flutter']['assets'], ['assets/']);
    expect(yaml['dependencies'].containsKey('unused'), false);
    final journal = Directory('${root.path}/.janitor_backup')
        .listSync(recursive: true)
        .whereType<File>()
        .singleWhere((f) => f.path.endsWith('manifest.json'));
    for (var i = 0; i < 2; i++) {
      final restored = await run(root, ['clean', '--undo', journal.path]);
      expect(restored.exitCode, 0, reason: '${restored.stderr}');
    }
    expect(File('${root.path}/pubspec.yaml').readAsBytesSync(), original);
    expect(File('${root.path}/explicit.png').readAsStringSync(), 'explicit');
  });
  for (final response in ['n\n', '']) {
    test('CLI interactive rejection/EOF ($response) cannot delete', () async {
      final root = await fixture.project();
      final child = await Process.start(
          executable,
          [
            '--packages=$packages',
            cli,
            'clean',
            '--remove-asset',
            'explicit.png',
            '--apply',
            '--interactive'
          ],
          workingDirectory: root.path);
      final output = child.stdout.transform(utf8.decoder).join();
      final error = child.stderr.transform(utf8.decoder).join();
      child.stdin.write(response);
      await child.stdin.close();
      expect(await child.exitCode, 0, reason: await error);
      expect(await output, contains('Applied: **no**'));
      expect(File('${root.path}/explicit.png').existsSync(), true);
    });
  }
  test('CLI reports invalid inputs with nonzero exit and no stack trace',
      () async {
    final root = await fixture.project();
    final invalid = await run(
        root, ['clean', '--remove-asset', '../escape.png', '--apply', '--yes']);
    expect(invalid.exitCode, 2);
    expect(invalid.stderr, contains('Cannot remove'));
    expect(invalid.stderr, isNot(contains('#0')));
    final help = await run(root, ['clean', '--help']);
    expect(help.exitCode, 0);
    expect(help.stdout, contains('--remove-asset'));
  });
  test('CLI refuses to overwrite an existing output file', () async {
    final root = await fixture.project();
    final before = File('${root.path}/pubspec.yaml').readAsStringSync();
    final result = await run(root, ['scan', '--output', 'pubspec.yaml']);
    expect(result.exitCode, 2);
    expect(File('${root.path}/pubspec.yaml').readAsStringSync(), before);
  });
}
