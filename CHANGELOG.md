## 1.1.0

- Resolve project-root aliases (including macOS temporary paths) consistently
  for scan, cleanup, absolute backup paths and undo. Keep symlinks below the
  project root and untrusted journal paths prohibited; add alias and containment
  regressions.

- Review fixes: normalize internal Windows paths without relaxing input checks;
  protect pubspec licenses/shaders/deferred assets; honor workspace overrides;
  verify automatic rollback before manual recovery and add Windows CI.

- Safety change: missing references/imports now produce review-only candidates.
  Cleanup requires exact `--remove-asset`, `--remove-dependency`, or
  `--remove-dev-dependency` selections plus confirmation; no unknown item is
  automatically deleted. Existing scan/clean commands and public types remain.
- Fix interactive rejection/EOF applying cleanup; list exact selected paths.
- Scan project-wide Dart, generated, tooling, CI, native and web references;
  handle conditional package directives, root-level paths and dynamic uncertainty.
- Respect non-recursive Flutter asset directories; protect resolution variants,
  absent logical bases, fonts and configured map-valued asset declarations.
- Update explicit asset declarations and dependencies with structural YAML edits
  and semantic validation. Refuse unsupported alias edits.
- Add unique operation backups, pre-mutation recovery journals, content hashes,
  rollback, retryable/conflict-aware undo, project binding and symlink/path checks.
  Unsafe legacy YAML recovery manifests require manual recovery.
- Make workspaces report-only. Stop implicit consumer `pub get`; optional checks
  run in disposable copies and choose the appropriate Dart/Flutter executable.
- Add false-positive, transaction failure, interruption, restore, YAML and CLI
  regressions. Keep development dependencies compatible with Dart 3.4.
- Exclude editor files, tests/fixtures and local artifacts from published contents.

## 1.0.1

- Added package-level API documentation comments for public API elements.
- Added runnable `example/flutter_janitor_example.dart`.
- Improved README with example usage guidance.

## 1.0.0

- Initial public release of `flutter_janitor`.
- Added `scan` and `clean` CLI commands.
- Added unused asset detection with safe/unsafe buckets.
- Added unused dependency detection with tooling-aware unsafe bucket.
- Added safe cleanup apply, backup manifest, and undo.
- Added Markdown/Text report writers.
- Added unit tests and fixture-based end-to-end tests.
- Added CI workflow and publishing guide.
