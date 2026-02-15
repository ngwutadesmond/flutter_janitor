import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';
import 'path_utils.dart';
import 'pubspec_parser.dart';

class NativeReferenceScanner {
  static final RegExp _stringRegex = RegExp(
    r'''["']([^"']*assets\/[^"']*)["']''',
  );

  Future<DartReferenceScanResult> scan({required String projectRoot}) async {
    final result = DartReferenceScanResult();

    for (final root in const ['ios', 'android']) {
      final directory = Directory(p.join(projectRoot, root));
      if (!await directory.exists()) {
        continue;
      }
      await for (final entity
          in directory.list(recursive: true, followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final content = await entity.readAsString();
        for (final match in _stringRegex.allMatches(content)) {
          final literal = normalizePath(match.group(1)!);
          final extension = p.extension(literal).toLowerCase();
          if (PubspecParser.supportedAssetExtensions.contains(extension)) {
            result.usedAssets.add(literal);
          } else {
            result.unsafeAssetPrefixes.add(ensureTrailingSlash(literal));
          }
        }
      }
    }

    return result;
  }
}
