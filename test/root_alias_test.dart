import 'dart:convert';
import 'dart:io';

import 'package:flutter_janitor/flutter_janitor.dart';
import 'package:flutter_janitor/src/cleaner.dart';
import 'package:flutter_janitor/src/project_walker.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'safety_test.dart' as fixture;

Future<Directory> aliasFor(Directory root) async {
  final holder = await Directory.systemTemp.createTemp('janitor-root-alias-');
  addTearDown(() => holder.delete(recursive: true));
  final alias = Link(p.join(holder.path, 'project'));
  await alias.create(await root.resolveSymbolicLinks());
  return Directory(alias.path);
}

String throughRoot(Directory root, CleanManifest manifest) => p.join(
    root.path, p.relative(manifest.manifestPath, from: manifest.projectRoot));

void main() {
  test('default system temp root supports scan, absolute backup and undo',
      () async {
    // Keep the OS-provided path spelling: /var/folders on macOS is the regression.
    final root = await fixture.project();
    final original = File(p.join(root.path, 'pubspec.yaml')).readAsBytesSync();
    final engine = JanitorEngine();
    final scan = await engine.scan(projectRoot: root.path);
    expect(scan.projectRoot, p.normalize(await root.resolveSymbolicLinks()));
    expect(scan.pubspec.declaredAssets, contains('explicit.png'));
    final files = await ProjectWalker(projectRoot: root.path, excludeRoots: {})
        .listProjectFiles();
    expect(files, contains('lib/main.dart'));
    expect(files.any((file) => file.contains('..')), false);
    final clean = await engine.clean(
        projectRoot: root.path,
        options: CleanOptions(
            apply: true,
            yes: true,
            reviewedAssets: {'explicit.png'},
            backupDir: p.join(root.path, 'custom', 'backup')));
    expect(clean.applied, true);
    expect(clean.manifest!.projectRoot, scan.projectRoot);
    expect(File(p.join(root.path, 'explicit.png')).existsSync(), false);
    expect(
        await engine.undo(throughRoot(root, clean.manifest!),
            projectRoot: scan.projectRoot),
        1);
    expect(
        await engine.undo(clean.manifest!.manifestPath, projectRoot: root.path),
        0);
    expect(File(p.join(root.path, 'pubspec.yaml')).readAsBytesSync(), original);
    expect(
        File(p.join(root.path, 'explicit.png')).readAsStringSync(), 'explicit');
  });

  group('root aliases preserve descendant boundaries', () {
    test('explicit root alias supports cleanup and absolute alias undo',
        () async {
      final root = await fixture.project();
      final alias = await aliasFor(root);
      final clean = await JanitorEngine().clean(
          projectRoot: alias.path,
          options: CleanOptions(
              apply: true,
              yes: true,
              reviewedAssets: {'explicit.png'},
              backupDir: p.join(alias.path, 'new', 'backup')));
      expect(clean.applied, true);
      expect(clean.manifest!.projectRoot,
          p.normalize(await root.resolveSymbolicLinks()));
      expect(
          await JanitorEngine().undo(throughRoot(alias, clean.manifest!),
              projectRoot: root.path),
          1);
      expect(File(p.join(root.path, 'explicit.png')).readAsStringSync(),
          'explicit');
    });

    test('approval cannot retarget the operation through its root alias',
        () async {
      final root = await fixture.project();
      final outside = await fixture.project();
      final alias = await aliasFor(root);
      final clean = await JanitorEngine().clean(
          projectRoot: alias.path,
          options: const CleanOptions(
              apply: true, interactive: true, reviewedAssets: {'explicit.png'}),
          approvalCallback: (_) async {
            await Link(alias.path).delete();
            await Link(alias.path).create(await outside.resolveSymbolicLinks());
            return true;
          });
      expect(clean.applied, true);
      expect(clean.manifest!.projectRoot,
          p.normalize(await root.resolveSymbolicLinks()));
      expect(File(p.join(root.path, 'explicit.png')).existsSync(), false);
      expect(File(p.join(outside.path, 'explicit.png')).readAsStringSync(),
          'explicit');
      await fixture.undo(root, clean.manifest!);
    });

    for (final external in [false, true]) {
      test('absolute alias backup refuses descendant link, external=$external',
          () async {
        final root = await fixture.project();
        final outside = await fixture.project();
        final alias = await aliasFor(root);
        final target = external ? outside : root;
        await Link(p.join(root.path, 'linked'))
            .create(await target.resolveSymbolicLinks());
        for (final backup in [
          'linked/backup',
          p.join(alias.path, 'linked', 'backup')
        ]) {
          await expectLater(
              fixture.apply(root, backup: backup), throwsStateError);
        }
        expect(File(p.join(root.path, 'assets/remove.png')).readAsStringSync(),
            'remove');
        expect(Directory(p.join(target.path, 'backup')).existsSync(), false);
      });
    }

    test('absolute alias manifest refuses file and directory symlinks',
        () async {
      final root = await fixture.project();
      final alias = await aliasFor(root);
      final manifest = await fixture.apply(root);
      await Link(p.join(root.path, 'manifest-link.json'))
          .create(manifest.manifestPath);
      await Link(p.join(root.path, 'operation-link'))
          .create(p.dirname(manifest.manifestPath));
      for (final path in [
        p.join(alias.path, 'manifest-link.json'),
        p.join(alias.path, 'operation-link', 'manifest.json')
      ]) {
        await expectLater(
            Cleaner().undo(manifestPath: path, projectRoot: root.path),
            throwsStateError);
      }
      expect(File(p.join(root.path, 'assets/remove.png')).existsSync(), false);
      expect(await fixture.undo(root, manifest), 1);
    });

    test('shortcut directly into a backup is not accepted as a root alias',
        () async {
      final root = await fixture.project();
      final manifest = await fixture.apply(root);
      final shortcut =
          await aliasFor(Directory(p.dirname(manifest.manifestPath)));
      await expectLater(
          Cleaner().undo(
              manifestPath: p.join(shortcut.path, 'manifest.json'),
              projectRoot: root.path),
          throwsStateError);
      expect(await fixture.undo(root, manifest), 1);
    });

    test('alias handling never resolves tampered journal fields', () async {
      final root = await fixture.project();
      final alias = await aliasFor(root);
      final manifest = await fixture.apply(root);
      final file = File(manifest.manifestPath);
      final original = await file.readAsString();
      for (final field in ['project_root', 'operation', 'entry']) {
        final journal = jsonDecode(original) as Map<String, dynamic>;
        if (field == 'entry') {
          (journal['entries'] as List).first['path'] =
              p.join(alias.path, 'assets', 'remove.png');
        } else {
          journal[field] = field == 'project_root'
              ? alias.path
              : p.dirname(throughRoot(alias, manifest));
        }
        await file.writeAsString(jsonEncode(journal));
        await expectLater(
            Cleaner().undo(
                manifestPath: throughRoot(alias, manifest),
                projectRoot: root.path),
            throwsStateError);
        expect(
            File(p.join(root.path, 'assets/remove.png')).existsSync(), false);
      }
      await file.writeAsString(original);
      expect(await fixture.undo(root, manifest), 1);
    });

    test('alias paths still reject traversal and a symlinked backup tree',
        () async {
      final root = await fixture.project();
      final alias = await aliasFor(root);
      await expectLater(
          fixture.apply(root, backup: '${alias.path}/assets/../backup'),
          throwsStateError);
      final manifest = await fixture.apply(root);
      final before =
          Directory(p.join(p.dirname(manifest.manifestPath), 'before'));
      final moved = await before.rename('${before.path}-moved');
      await Link(before.path).create(moved.path);
      await expectLater(
          Cleaner().undo(
              manifestPath: throughRoot(alias, manifest),
              projectRoot: root.path),
          throwsStateError);
      expect(File(p.join(root.path, 'assets/remove.png')).existsSync(), false);
    });
  }, skip: Platform.isWindows ? 'Requires symlink privileges' : false);
}
