import 'dart:io';
import 'package:path/path.dart' as p;

String normalizePath(String path) => p.normalize(path).replaceAll('\\', '/');
String toProjectRelative(String projectRoot, String path) => normalizePath(
    p.relative(p.isAbsolute(path) ? path : p.join(projectRoot, path),
        from: projectRoot));
String toProjectAbsolute(String projectRoot, String path) =>
    normalizePath(p.isAbsolute(path) ? path : p.join(projectRoot, path));
bool isWithinExcludedRoot(String relPath, Set<String> excludedRoots) =>
    excludedRoots.any((root) =>
        relPath == normalizePath(root) ||
        relPath.startsWith('${normalizePath(root)}/'));
String ensureTrailingSlash(String value) => '${normalizePath(value)}/';
Future<void> ensureParentDirectory(String path) =>
    File(path).parent.create(recursive: true);

/// Reject absolute paths, traversal, portable drive paths, and every symlink
/// component, including dangling links. Call again immediately before mutations.
String checkedPath(String root, String relative) {
  if (relative.isEmpty ||
      p.isAbsolute(relative) ||
      p.windows.isAbsolute(relative) ||
      relative.contains('\\') ||
      relative.split('/').contains('..') ||
      relative.contains('\u0000')) {
    throw StateError('Unsafe project path: $relative');
  }
  final base = p.normalize(p.absolute(root));
  final target = p.normalize(p.join(base, relative));
  if (!p.isWithin(base, target)) {
    throw StateError('Path leaves project: $relative');
  }
  var current = p.rootPrefix(target);
  for (final component in p.split(target).skip(1)) {
    current = p.join(current, component);
    if (FileSystemEntity.typeSync(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('Symlink path is not supported: $current');
    }
  }
  return target;
}

String checkedRoot(String root) {
  final absolute = p.normalize(p.absolute(root));
  checkedPath(p.dirname(absolute), p.basename(absolute));
  if (!Directory(absolute).existsSync()) {
    throw StateError('Project directory not found: $root');
  }
  return absolute;
}
