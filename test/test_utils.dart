import 'dart:io';

import 'package:path/path.dart' as p;

Future<Directory> copyFixtureToTemp(String fixtureName) async {
  final sourceRoot = p.join('test', 'fixtures', fixtureName);
  final destination = await Directory.systemTemp.createTemp('flutter_janitor_');
  final sourceDirectory = Directory(sourceRoot);

  await for (final entity in sourceDirectory.list(
    recursive: true,
    followLinks: false,
  )) {
    final relative = p.relative(entity.path, from: sourceRoot);
    final targetPath = p.join(destination.path, relative);

    if (entity is Directory) {
      await Directory(targetPath).create(recursive: true);
      continue;
    }

    if (entity is File) {
      await File(targetPath).parent.create(recursive: true);
      await File(targetPath).writeAsBytes(await entity.readAsBytes());
    }
  }

  return destination;
}
