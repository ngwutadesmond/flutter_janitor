import 'dart:io';

import 'package:flutter_janitor/src/cleaner.dart';
import 'package:flutter_janitor/src/models.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Cleaner', () {
    test(
      'creates backup manifest, applies cleanup, and undo restores',
      () async {
        final projectDir = await Directory.systemTemp.createTemp(
          'flutter_janitor_cleaner_',
        );
        addTearDown(() => projectDir.delete(recursive: true));

        await Directory(
          p.join(projectDir.path, 'assets/images'),
        ).create(recursive: true);
        final assetFile = File(
          p.join(projectDir.path, 'assets/images/remove.png'),
        );
        await assetFile.writeAsString('remove-me');

        final pubspecFile = File(p.join(projectDir.path, 'pubspec.yaml'));
        await pubspecFile.writeAsString('''
name: sample

environment:
  sdk: '>=3.4.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  provider: ^6.1.0
  http: ^1.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  mocktail: ^1.0.0
''');

        final cleaner = Cleaner();
        final manifest = await cleaner.apply(
          projectRoot: projectDir.path,
          plan: const CleanActionPlan(
            assetPaths: {'assets/images/remove.png'},
            removeDependencies: {'provider'},
            removeDevDependencies: {'mocktail'},
          ),
          backupDir: '.janitor_backup',
        );

        expect(await assetFile.exists(), isFalse);
        expect(await File(manifest.manifestPath).exists(), isTrue);

        final updatedPubspec = await pubspecFile.readAsString();
        expect(updatedPubspec.contains('provider:'), isFalse);
        expect(updatedPubspec.contains('mocktail:'), isFalse);

        final restoredCount = await cleaner.undo(
          manifestPath: manifest.manifestPath,
        );
        expect(restoredCount, 1);
        expect(await assetFile.exists(), isTrue);

        final restoredPubspec = await pubspecFile.readAsString();
        expect(restoredPubspec.contains('provider:'), isTrue);
        expect(restoredPubspec.contains('mocktail:'), isTrue);
      },
    );
  });
}
