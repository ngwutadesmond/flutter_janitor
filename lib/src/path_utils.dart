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

/// Resolve the caller-selected project boundary, including OS aliases such as
/// macOS /var and /tmp. Descendant paths must still go through [checkedPath].
String checkedRoot(String root) {
  final absolute = p.normalize(p.absolute(root));
  if (!Directory(absolute).existsSync()) {
    throw StateError('Project directory not found: $root');
  }
  return p.normalize(Directory(absolute).resolveSymbolicLinksSync());
}

/// Accept a caller-supplied path under an already canonical project root.
/// Resolve aliases only until a prefix identifies that exact root; never resolve
/// links in the remaining suffix, even if they point back inside the project.
/// Journal fields and asset selections must use [checkedPath] directly.
String checkedProjectPath(String root, String path) {
  if (!p.isAbsolute(path)) return checkedPath(root, path);
  final parts = p.split(path);
  if (parts.contains('..') || path.contains('\u0000')) {
    throw StateError('Unsafe project path: $path');
  }
  var prefix = parts.first;
  for (var index = 1; index < parts.length; index++) {
    final directory = Directory(prefix);
    if (!directory.existsSync()) break;
    if (p.equals(directory.resolveSymbolicLinksSync(), root)) {
      return checkedPath(root, parts.skip(index).join('/'));
    }
    prefix = p.join(prefix, parts[index]);
  }
  throw StateError('Path is not inside the project: $path');
}

/// Converts an OS-generated relative path into the portable form accepted by
/// [checkedPath]. Do not use this to sanitize an untrusted manifest path.
String portableRelativePath(String path,
        {required String from, p.Context? context}) =>
    (context ?? p.context).relative(path, from: from).replaceAll('\\', '/');
