import 'dart:convert';
import 'dart:io';
import 'package:flutter_janitor/flutter_janitor.dart';
import 'package:flutter_janitor/src/cleaner.dart';
import 'package:flutter_janitor/src/pubspec_editor.dart';
import 'package:flutter_janitor/src/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<Directory> project({String? manifest}) async {
  final root = await Directory.systemTemp.createTemp('janitor-safety-');
  addTearDown(() => root.delete(recursive: true));
  await put(
      root,
      'pubspec.yaml',
      manifest ??
          '''
name: sample
publish_to: none
environment:
  sdk: '>=3.4.0 <4.0.0'
dependencies:
  unused: ^1.0.0
dev_dependencies:
  unused_dev: ^1.0.0
flutter:
  assets:
    - assets/
    - explicit.png
''');
  await put(root, 'assets/remove.png', 'remove');
  await put(root, 'explicit.png', 'explicit');
  await put(root, 'lib/main.dart', 'void main() {}');
  return root;
}

Future<void> put(Directory root, String name, String content) async {
  final file = File(p.join(root.path, name));
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

const assetPlan = CleanActionPlan(
    assetPaths: {'assets/remove.png'},
    removeDependencies: {},
    removeDevDependencies: {});
const allPlan = CleanActionPlan(
    assetPaths: {'assets/remove.png', 'explicit.png'},
    removeDependencies: {'unused'},
    removeDevDependencies: {'unused_dev'});
Future<CleanManifest> apply(Directory root,
        {Cleaner? cleaner,
        CleanActionPlan plan = assetPlan,
        String backup = '.janitor_backup'}) =>
    (cleaner ?? Cleaner())
        .apply(projectRoot: root.path, plan: plan, backupDir: backup);
Future<int> undo(Directory root, CleanManifest manifest, {Cleaner? cleaner}) =>
    (cleaner ?? Cleaner())
        .undo(projectRoot: root.path, manifestPath: manifest.manifestPath);

void main() {
  group('review and approval', () {
    test('unreferenced is uncertain, default apply never deletes', () async {
      final root = await project();
      final result = await JanitorEngine().clean(
          projectRoot: root.path,
          options: const CleanOptions(apply: true, yes: true));
      expect(result.applied, false);
      expect(result.plan.hasChanges, false);
      expect(result.scanResult.assetAnalysis.unusedSafe, isEmpty);
      expect(result.scanResult.dependencyAnalysis.unusedSafe, isEmpty);
      expect(result.scanResult.dependencyAnalysis.unsafeReasons['unused'],
          contains('native plugins'));
      expect(File('${root.path}/assets/remove.png').existsSync(), true);
      expect(Directory('${root.path}/.janitor_backup').existsSync(), false);
    });
    for (final callback in [false, null]) {
      test('interactive with approval $callback never bypasses confirmation',
          () async {
        final root = await project();
        final result = await JanitorEngine().clean(
            projectRoot: root.path,
            options: const CleanOptions(
                apply: true,
                interactive: true,
                reviewedAssets: {'assets/remove.png'}),
            approvalCallback: callback == null ? null : (_) async => callback);
        expect(result.applied, false);
        expect(File('${root.path}/assets/remove.png').existsSync(), true);
      });
    }
    test('selected dry-run is read only and approved selection is recoverable',
        () async {
      final root = await project();
      final engine = JanitorEngine();
      final dry = await engine.clean(
          projectRoot: root.path,
          options: const CleanOptions(
              reviewedAssets: {'explicit.png'},
              reviewedDependencies: {'unused'}));
      expect(dry.plan.assetPaths, {'explicit.png'});
      expect(dry.applied, false);
      expect(File('${root.path}/.janitor-lock').existsSync(), false);
      final original = File('${root.path}/pubspec.yaml').readAsStringSync();
      final result = await engine.clean(
          projectRoot: root.path,
          options: const CleanOptions(
              apply: true,
              yes: true,
              reviewedAssets: {'explicit.png'},
              reviewedDependencies: {'unused'}));
      expect(result.applied, true);
      expect(File('${root.path}/explicit.png').existsSync(), false);
      final yaml =
          loadYaml(File('${root.path}/pubspec.yaml').readAsStringSync());
      expect(yaml['flutter']['assets'], ['assets/']);
      expect(yaml['dependencies'].containsKey('unused'), false);
      await engine.undo(result.manifest!.manifestPath, projectRoot: root.path);
      expect(File('${root.path}/pubspec.yaml').readAsStringSync(), original);
    });
    test('positive source/config evidence cannot be selected', () async {
      final root = await project();
      await put(root, 'web/index.html', '<img src="explicit.png">');
      await put(root, '.github/workflows/build.yml', 'run: dart run unused');
      for (final options in [
        const CleanOptions(reviewedAssets: {'explicit.png'}),
        const CleanOptions(reviewedDependencies: {'unused'})
      ]) {
        await expectLater(
            JanitorEngine().clean(projectRoot: root.path, options: options),
            throwsStateError);
      }
    });
    test('workspaces refuse mutation before checks or backups', () async {
      final root = await project();
      await put(
          root, 'pubspec.yaml', 'name: sample\nworkspace: [packages/a]\n');
      expect(
          (await JanitorEngine().scan(projectRoot: root.path))
              .pubspec
              .reportOnlyReasons,
          isNotEmpty);
      await expectLater(
          JanitorEngine().clean(
              projectRoot: root.path,
              options: const CleanOptions(apply: true, yes: true)),
          throwsStateError);
      expect(Directory('${root.path}/.janitor_backup').existsSync(), false);
    });
  });

  group('transaction and recovery', () {
    test('restoration preserves BOM bytes and file permissions', () async {
      final root = await project();
      final pubspec = File('${root.path}/pubspec.yaml');
      final before = <int>[239, 187, 191, ...pubspec.readAsBytesSync()];
      await pubspec.writeAsBytes(before);
      if (!Platform.isWindows) {
        final chmod = await Process.run(
            'chmod', ['750', '${root.path}/assets/remove.png']);
        expect(chmod.exitCode, 0);
      }
      final mode = File('${root.path}/assets/remove.png').statSync().mode;
      final manifest = await apply(root, plan: allPlan);
      await undo(root, manifest);
      expect(pubspec.readAsBytesSync(), before);
      expect(File('${root.path}/assets/remove.png').statSync().mode, mode);
    });
    test('unique operations preserve earlier backup content', () async {
      final root = await project();
      final first = await apply(root);
      await put(root, 'assets/remove.png', 'second');
      final second = await apply(root);
      expect(first.manifestPath, isNot(second.manifestPath));
      expect(File(first.movedFiles.single.backupPath).readAsStringSync(),
          'remove');
      expect(File(second.movedFiles.single.backupPath).readAsStringSync(),
          'second');
      await undo(root, second);
      await expectLater(undo(root, first), throwsStateError);
      expect(
          File('${root.path}/assets/remove.png').readAsStringSync(), 'second');
    });
    for (final phase in [
      'journal-ready',
      'changed:assets/remove.png',
      'changed:explicit.png',
      'changed:pubspec.yaml',
      'applied'
    ]) {
      test('failure at $phase retains recovery evidence', () async {
        final root = await project();
        final before = File('${root.path}/pubspec.yaml').readAsStringSync();
        final cleaner = Cleaner(checkpoint: (at) async {
          if (at == phase) throw StateError('injected');
        });
        await expectLater(
            apply(root, cleaner: cleaner, plan: allPlan), throwsStateError);
        final journals = Directory('${root.path}/.janitor_backup')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('manifest.json'))
            .toList();
        expect(journals, hasLength(1));
        await Cleaner()
            .undo(manifestPath: journals.single.path, projectRoot: root.path);
        expect(File('${root.path}/assets/remove.png').readAsStringSync(),
            'remove');
        expect(
            File('${root.path}/explicit.png').readAsStringSync(), 'explicit');
        expect(File('${root.path}/pubspec.yaml').readAsStringSync(), before);
      });
    }
    for (final phase in ['changed:assets/remove.png', 'changed:pubspec.yaml']) {
      test('process death at $phase leaves a usable durable journal', () async {
        final root = await project();
        final original = File('${root.path}/pubspec.yaml').readAsStringSync();
        final result = await Process.run(
            p.join(p.dirname(Platform.resolvedExecutable),
                'dart${Platform.isWindows ? '.exe' : ''}'),
            [
              '--packages=${p.absolute('.dart_tool/package_config.json')}',
              p.absolute('test/support/crash_worker.dart'),
              root.path,
              phase
            ]);
        expect(result.exitCode, 73, reason: '${result.stderr}');
        final journal = Directory('${root.path}/.janitor_backup')
            .listSync(recursive: true)
            .whereType<File>()
            .singleWhere((f) => f.path.endsWith('manifest.json'));
        await Cleaner()
            .undo(manifestPath: journal.path, projectRoot: root.path);
        expect(File('${root.path}/pubspec.yaml').readAsStringSync(), original);
        expect(File('${root.path}/assets/remove.png').readAsStringSync(),
            'remove');
        expect(
            File('${root.path}/explicit.png').readAsStringSync(), 'explicit');
      });
    }
    test('manifest write failure precedes every destructive operation',
        () async {
      final root = await project();
      final cleaner = Cleaner(checkpoint: (phase) async {
        if (phase.startsWith('before-journal:')) {
          await Directory(phase.substring('before-journal:'.length)).create();
        }
      });
      await expectLater(apply(root, cleaner: cleaner, plan: allPlan),
          throwsA(isA<FileSystemException>()));
      expect(
          File('${root.path}/assets/remove.png').readAsStringSync(), 'remove');
      expect(File('${root.path}/explicit.png').readAsStringSync(), 'explicit');
    });
    test('restore conflict preflight prevents partial restoration', () async {
      final root = await project();
      final manifest = await apply(root, plan: allPlan);
      await put(root, 'explicit.png', 'new user data');
      await expectLater(undo(root, manifest), throwsStateError);
      expect(File('${root.path}/assets/remove.png').existsSync(), false);
      expect(File('${root.path}/explicit.png').readAsStringSync(),
          'new user data');
    });
    test('changed pubspec aborts restore before assets', () async {
      final root = await project();
      final manifest = await apply(root, plan: allPlan);
      await File('${root.path}/pubspec.yaml')
          .writeAsString('# user edit\n', mode: FileMode.append);
      await expectLater(undo(root, manifest), throwsStateError);
      expect(File('${root.path}/assets/remove.png').existsSync(), false);
    });
    test('interrupted restore can be retried and repeated undo is a no-op',
        () async {
      final root = await project();
      final manifest = await apply(root, plan: allPlan);
      final cleaner = Cleaner(checkpoint: (phase) async {
        if (phase == 'restored:assets/remove.png') {
          throw StateError('interrupted');
        }
      });
      await expectLater(
          undo(root, manifest, cleaner: cleaner), throwsStateError);
      expect(await undo(root, manifest), 1);
      expect(await undo(root, manifest), 0);
      expect(File(manifest.movedFiles.first.backupPath).existsSync(), true);
    });
    test('corrupt backup aborts before mutation', () async {
      final root = await project();
      final manifest = await apply(root);
      await File(manifest.movedFiles.single.backupPath)
          .writeAsString('corrupt');
      await expectLater(undo(root, manifest), throwsStateError);
      expect(File('${root.path}/assets/remove.png').existsSync(), false);
    });
    test('failed edit leaves every asset intact', () async {
      final root = await project();
      await expectLater(
          apply(root, cleaner: Cleaner(pubspecEditor: FailingEditor())),
          throwsStateError);
      expect(File('${root.path}/assets/remove.png').existsSync(), true);
      expect(Directory('${root.path}/.janitor_backup').existsSync(), false);
    });
    test('backup preparation failure leaves every asset intact', () async {
      final root = await project();
      await put(root, 'not-a-directory', 'block backup');
      await expectLater(apply(root, backup: 'not-a-directory/backup'),
          throwsA(isA<FileSystemException>()));
      expect(File('${root.path}/assets/remove.png').existsSync(), true);
    });
    test('snapshot change after journal is not overwritten', () async {
      final root = await project();
      final cleaner = Cleaner(checkpoint: (phase) async {
        if (phase == 'journal-ready') {
          await put(root, 'assets/remove.png', 'concurrent edit');
        }
      });
      await expectLater(apply(root, cleaner: cleaner), throwsStateError);
      expect(File('${root.path}/assets/remove.png').readAsStringSync(),
          'concurrent edit');
    });
  });

  group('path and journal boundaries', () {
    for (final path in [
      '../escape.png',
      '/tmp/escape.png',
      'assets/../../escape.png',
      r'C:\escape.png',
      r'assets\..\escape.png'
    ]) {
      test('rejects asset path $path', () async {
        final root = await project();
        await expectLater(
            apply(root,
                plan: CleanActionPlan(
                    assetPaths: {path},
                    removeDependencies: {},
                    removeDevDependencies: {})),
            throwsStateError);
        expect(File('${root.path}/assets/remove.png').existsSync(), true);
      });
    }
    test('external and sibling-prefix backups are rejected', () async {
      final root = await project();
      for (final path in [
        '/tmp/external-backup',
        '${root.path}-sibling',
        '../outside'
      ]) {
        await expectLater(apply(root, backup: path), throwsStateError);
      }
    });
    test('symlink source, ancestor and backup are rejected', () async {
      final root = await project();
      final outside = await project();
      await Link('${root.path}/linked').create(outside.path);
      await expectLater(apply(root, backup: 'linked/backup'), throwsStateError);
      await File('${root.path}/assets/remove.png').delete();
      await Link('${root.path}/assets/remove.png')
          .create('${outside.path}/assets/remove.png');
      await expectLater(apply(root), throwsStateError);
      expect(File('${outside.path}/assets/remove.png').readAsStringSync(),
          'remove');
    }, skip: Platform.isWindows ? 'Requires symlink privileges' : false);
    test('tampered traversal and project mismatch journals cannot restore',
        () async {
      final root = await project();
      final other = await project();
      final manifest = await apply(root);
      await expectLater(
          Cleaner().undo(
              manifestPath: manifest.manifestPath, projectRoot: other.path),
          throwsStateError);
      final file = File(manifest.manifestPath);
      final journal =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      (journal['entries'] as List).first['path'] = '../escape.png';
      await file.writeAsString(jsonEncode(journal));
      await expectLater(undo(root, manifest), throwsStateError);
    });
    test('symlinked restore directory is rejected', () async {
      final root = await project();
      final outside = await project();
      final manifest = await apply(root);
      await Directory('${root.path}/assets').delete();
      await Link('${root.path}/assets').create(outside.path);
      await expectLater(undo(root, manifest), throwsStateError);
      expect(File('${outside.path}/assets/remove.png').readAsStringSync(),
          'remove');
    }, skip: Platform.isWindows ? 'Requires symlink privileges' : false);
  });

  group('source coverage and resource semantics', () {
    test('directory entries exclude unrelated descendants and include variants',
        () async {
      final root = await project();
      await put(root, 'assets/nested/unbundled.png', 'nested');
      await put(root, 'assets/2.0x/remove.png', 'variant');
      await put(root, 'assets/3.0x/absent.png', 'fallback');
      await put(root, 'lib/main.dart',
          "void main() { Image.asset('assets/remove.png'); Image.asset('assets/absent.png'); }");
      final scan = await JanitorEngine().scan(projectRoot: root.path);
      expect(scan.pubspec.declaredAssets,
          isNot(contains('assets/nested/unbundled.png')));
      expect(scan.assetAnalysis.used,
          containsAll(['assets/2.0x/remove.png', 'assets/3.0x/absent.png']));
      expect(scan.assetAnalysis.missingReferences,
          isNot(contains('assets/absent.png')));
      await expectLater(apply(root), throwsStateError);
    });
    test(
        'map assets, fonts, font fallback and package asset declarations survive',
        () async {
      final root = await project(manifest: '''
name: sample
flutter:
  assets:
    - path: explicit.png
      flavors: [paid]
      transformers:
        - package: transformer
    - packages/art/icons/icon.png
  fonts:
    - family: ThemeFont
      fonts:
        - asset: assets/remove.png
dependencies:
  transformer: any
  art: any
  font_pkg: any
  native_impl: any
  flutter:
    sdk: flutter
  unused: any
flutter_gen:
  integration: font_pkg
''');
      final scan = await JanitorEngine().scan(projectRoot: root.path);
      expect(scan.assetAnalysis.used,
          containsAll(['explicit.png', 'assets/remove.png']));
      expect(scan.toolingHits.keys,
          containsAll(['transformer', 'art', 'font_pkg']));
      expect(scan.dependencyAnalysis.unusedSafe, isEmpty);
    });
    test(
        'bin, generated, conditional imports, parts, CI, config, native and web are scanned',
        () async {
      final root = await project();
      await put(root, 'bin/only.dart',
          "import 'package:unused/cli.dart' if (dart.library.io) 'package:alternative/io.dart';\npart 'package:part_pkg/shared.dart';");
      await put(root, 'lib/generated/assets.g.dart',
          "const asset = 'assets/remove.png';");
      await put(root, 'windows/runner/main.cpp',
          'lookupKeyForAsset("explicit.png");');
      await put(root, '.github/workflows/ci.yml', 'run: dart run unused_dev');
      await put(root, 'web/blob.bin', '\u0000\u0001');
      final scan = await JanitorEngine().scan(
          projectRoot: root.path,
          options: const ScanOptions(excludeDirs: {'bin', 'windows'}));
      expect(scan.dependencyAnalysis.used, contains('unused'));
      expect(
          scan.toolingHits['unused_dev'], contains('.github/workflows/ci.yml'));
      expect(scan.assetAnalysis.used,
          containsAll(['explicit.png', 'assets/remove.png']));
    });
    test(
        'ordinary interpolation, unknown arguments and generated wrappers never become safe',
        () async {
      final root = await project();
      await put(root, 'lib/main.dart',
          r'''void main() { Image.asset('assets/$name.png'); Image.asset(remotePath); Assets.images.logo.image(); }''');
      final scan = await JanitorEngine().scan(projectRoot: root.path);
      expect(scan.assetAnalysis.unusedSafe, isEmpty);
      expect(scan.assetAnalysis.unsafeReasons['assets/remove.png'],
          contains('Runtime interpolation'));
    });
    test('root-level path and arbitrary custom-loader literals are preserved',
        () async {
      final root = await project();
      await put(root, 'tool/custom.dart',
          "customLoader('explicit.png'); final path = 'assets/remove.png';");
      final scan = await JanitorEngine().scan(projectRoot: root.path);
      expect(scan.assetAnalysis.used,
          containsAll(['explicit.png', 'assets/remove.png']));
    });
  });

  group('checks', () {
    test('failed postflight rolls back changes and preserves the journal',
        () async {
      final root = await project();
      final original = File('${root.path}/pubspec.yaml').readAsStringSync();
      final result = await JanitorEngine(healthCheckRunner: FailPostflight())
          .clean(
              projectRoot: root.path,
              options: const CleanOptions(
                  apply: true, yes: true, reviewedAssets: {'explicit.png'}));
      expect(result.applied, false);
      expect(result.messages.join(' '), contains('rolled back'));
      expect(File('${root.path}/pubspec.yaml').readAsStringSync(), original);
      expect(File('${root.path}/explicit.png').existsSync(), true);
      expect(File(result.manifest!.manifestPath).existsSync(), true);
    });
    test('default checks have no process or resolution side effects', () async {
      final root = await project();
      final executor = FakeExecutor();
      expect(
          await HealthCheckRunner(executor: executor).runChecks(
              projectRoot: root.path, runAnalyze: false, runTests: false),
          isEmpty);
      expect(executor.calls, isEmpty);
    });
    test('Flutter checks select only Flutter and run in disposable copy',
        () async {
      final root = await project();
      final executor = FakeExecutor();
      final checks = await HealthCheckRunner(executor: executor)
          .runChecks(projectRoot: root.path, runAnalyze: true, runTests: true);
      expect(checks.every((r) => r.success), true);
      expect(executor.calls,
          ['flutter pub get', 'flutter analyze', 'flutter test']);
      expect(
          executor.directories
              .every((d) => d != root.path && !Directory(d).existsSync()),
          true);
      expect(File('${root.path}/pubspec.lock').existsSync(), false);
    });
  });
}

class FailingEditor extends PubspecEditor {
  @override
  String edit(String original, CleanActionPlan plan) =>
      throw StateError('injected edit failure');
}

class FakeExecutor implements CommandExecutor {
  final calls = <String>[];
  final directories = <String>[];
  @override
  Future<bool> commandExists(String executable) async => true;
  @override
  Future<RunResult> run(String executable, List<String> arguments,
      {required String workingDirectory}) async {
    calls.add('$executable ${arguments.join(' ')}');
    directories.add(workingDirectory);
    await File('$workingDirectory/pubspec.lock').writeAsString('generated');
    return RunResult(success: true, command: calls.last);
  }
}

class FailPostflight extends HealthCheckRunner {
  var calls = 0;
  @override
  Future<List<RunResult>> runChecks(
          {required String projectRoot,
          required bool runAnalyze,
          required bool runTests}) async =>
      [RunResult(success: ++calls == 1, command: 'injected check')];
}
