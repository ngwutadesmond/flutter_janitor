import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'models.dart';
import 'path_utils.dart';
import 'project_walker.dart';
import 'pubspec_parser.dart';

/// Optional legacy detail scan; project-wide evidence always includes native
/// and web files independently of this flag.
class NativeReferenceScanner {
  static final _strings = RegExp(r'''["']([^"']+)["']''');
  Future<DartReferenceScanResult> scan({required String projectRoot}) async {
    final root = checkedRoot(projectRoot);
    final result = DartReferenceScanResult();
    final files = await ProjectWalker(projectRoot: root, excludeRoots: {})
        .listProjectFiles(warnings: result.warnings);
    for (final path in files) {
      if (!{'ios', 'android', 'macos', 'windows', 'linux', 'web'}
          .contains(p.split(path).first)) {
        continue;
      }
      try {
        final file = File(checkedPath(root, path));
        if (await file.length() > 4 * 1024 * 1024) {
          result.warnings.add('Large native input omitted: $path');
          continue;
        }
        final content = utf8.decode(await file.readAsBytes());
        for (final match in _strings.allMatches(content)) {
          final literal = normalizePath(match.group(1)!);
          if (PubspecParser.supportedAssetExtensions
              .contains(p.extension(literal).toLowerCase())) {
            result.usedAssets.add(literal);
          }
        }
      } on FormatException catch (_) {
        continue;
      } on FileSystemException catch (_) {
        result.warnings.add('Unreadable native input: $path');
      }
    }
    return result;
  }
}
