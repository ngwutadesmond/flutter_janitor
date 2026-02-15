import 'dart:io';

import 'package:path/path.dart' as p;

String normalizePath(String path) {
  return p.normalize(path).replaceAll('\\', '/');
}

String toProjectRelative(String projectRoot, String path) {
  final absolute = p.isAbsolute(path) ? path : p.join(projectRoot, path);
  return normalizePath(p.relative(absolute, from: projectRoot));
}

String toProjectAbsolute(String projectRoot, String path) {
  return p.isAbsolute(path)
      ? normalizePath(path)
      : normalizePath(p.join(projectRoot, path));
}

bool isWithinExcludedRoot(String relPath, Set<String> excludedRoots) {
  final normalized = normalizePath(relPath);
  for (final root in excludedRoots) {
    final candidate = normalizePath(root);
    if (normalized == candidate || normalized.startsWith('$candidate/')) {
      return true;
    }
  }
  return false;
}

String ensureTrailingSlash(String value) {
  final normalized = normalizePath(value);
  if (normalized.isEmpty) {
    return normalized;
  }
  return normalized.endsWith('/') ? normalized : '$normalized/';
}

Future<void> ensureParentDirectory(String path) async {
  final parent = File(path).parent;
  if (!await parent.exists()) {
    await parent.create(recursive: true);
  }
}
