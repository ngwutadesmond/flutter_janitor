# flutter_janitor

Review Flutter project resources and dependencies, then remove **explicitly selected, manually reviewed** items with recoverable backups.

Static analysis cannot prove that a resource or package is unused. Runtime paths, generated code, plugins, assets supplied to consumers, build hooks and external tooling can all hide usage. **No unknown item is deleted automatically.** In particular, missing text imports are not sufficient evidence to remove a dependency.

## Install and scan

```sh
dart pub global activate flutter_janitor
cd /path/to/project
flutter_janitor scan --format text
```

Scan is read-only unless you request a new report with `--output report.md`. Existing report destinations are never overwritten. Reports list unreferenced candidates with reasons and missing references. Used resources are retained; source-level used sets are also available through the Dart API. The legacy “safe” buckets remain in the API/report format but are empty: absence of evidence is not proof of non-use.

The scan covers Dart files throughout the project, including `bin`, tests, tools, generated sources and nested packages. It also searches configuration, CI, web and native text files. It retains package references in conditional imports/exports, parts, package assets/fonts and tooling configuration. Caches and dependency output (`.git`, `.dart_tool`, `build`, `.janitor_backup`, `node_modules`, `Pods`, `.gradle`, `.symlinks`) are omitted. The compatibility `--include` and `--exclude` options do not narrow this safety scan; native/web evidence is always collected. `--include-native-scan` adds legacy native reference details.

Flutter directory declarations include immediate files and resolution variants, not arbitrary descendants. Font declarations, configured map-valued assets (flavors/platforms/transformers), and resolution groups are protected from cleanup. This includes logical images whose base file is absent but valid variants exist.

## Review, preview, apply

Before selecting an item, review the report and its source/configuration/runtime consumers. A candidate is **uncertain**, not a recommendation to delete it. Keep version control and a separate backup, and stop generators/editors/builds that could change the project during cleanup.

Select exact items you have established are unnecessary:

```sh
flutter_janitor clean \
  --remove-asset assets/obsolete.png \
  --remove-dependency old_package \
  --remove-dev-dependency old_generator
```

This only previews. Repeat each selection flag for multiple items. Commas in asset filenames are literal. Referenced, undeclared or protected items are rejected. Project tooling/configuration references also prevent dependency removal.

After reviewing the preview, repeat it with `--apply --interactive`, or use `--apply --yes` for already reviewed selections:

```sh
flutter_janitor clean --remove-asset assets/obsolete.png --apply --interactive
```

Rejecting the prompt or sending EOF makes no changes. `--yes` confirms only the exact selections; it never selects all report candidates. `clean --apply --yes` without selections does nothing.

Cleanup updates explicitly declared asset entries and dependency maps together with the selected files. Directory declarations remain valid. YAML edits are validated for unrelated semantic changes before files are modified; unsupported anchors/aliases are refused. Comments and formatting are preserved where supported by `yaml_edit`.

## Recovery

Each operation creates a unique directory:

```text
.janitor_backup/operation-…/manifest.json
.janitor_backup/operation-…/before/…
```

Complete backups and a versioned recovery journal are flushed **before** deletion or manifest replacement. Backups preserve exact file bytes. Restore preserves ordinary Unix permission bits using `chmod`; Windows permissions follow filesystem inheritance. Failed edits attempt automatic rollback. Interrupted operations retain the journal for recovery. Separate operations never reuse backup file paths.

From the **same project root**, restore the printed journal:

```sh
flutter_janitor clean --undo .janitor_backup/operation-EXAMPLE/manifest.json
```

Restore checks all backup SHA-256 digests and destination states first. It refuses changed files/pubspecs, wrong projects, traversal, external paths and symlinks rather than overwriting user work. Resolve conflicts manually against the retained `before` copies. Backups remain after restoration; repeated undo is a no-op. Treat journals as trusted local recovery data, not files to accept from third parties. Do not edit them.

`--backup-dir` must stay inside the project with no symlink components. File copies avoid relying on cross-device moves; replacements are staged next to their destination. Cooperating CLI processes use a project lock. This is not protection against malicious concurrent filesystem changes, power loss, unsupported filesystem semantics, or hardware failure.

Version 1.0.x YAML manifests lack integrity/post-edit evidence and are not automatically restored. Recover those backups manually into an isolated copy and review the diff. Keep old backups until recovery is verified.

## Optional verification and workspaces

Plain cleanup does **not** run `pub get` or modify lockfiles/package configuration. Resolve dependencies separately after reviewing the final diff.

```sh
flutter_janitor clean --remove-dependency old_package \
  --apply --yes --run-analyze --run-tests
```

Optional pre/post checks copy the project to a temporary directory and run `pub get`, then the requested checks there. Flutter projects use Flutter; Dart projects use Dart. Check scripts execute project code, so use this only for projects you trust. The original resolution files stay untouched. Missing SDKs or failing preflight checks abort; failing postflight checks roll back and return a nonzero CLI status. Relative path dependencies or scripts tied to their original location may fail in the copy; investigate rather than bypassing the failure.

Pub workspace roots and members are **report-only**, even with explicit selections. Cleanup refuses them because changing shared resolution state needs workspace-level recovery. Scan each member as needed; there is no automatic workspace dependency pruning.

## Limits

- This is conservative text/reference analysis, not a whole-program reachability proof. String matches can retain genuinely unused files; dynamic/external consumers can evade detection. Review is essential.
- Declared fonts, resolution groups and configured asset declarations require manual group-level edits. Arbitrary undeclared files are never cleanup targets.
- Binary and very large non-Dart inputs are not interpreted. Unreadable text, omitted large inputs, symlinks and dynamic references add uncertainty; invalid manifests/asset paths abort safely.
- Generated references are included when present. Absent generated code and remote configuration cannot establish non-use.
- Backups consume disk space. Keep them until the project has passed its own build and runtime checks.

Run `flutter_janitor clean --help` for options. The public Dart API remains available through `package:flutter_janitor/flutter_janitor.dart`; `CleanOptions.reviewedAssets`, `reviewedDependencies`, and `reviewedDevDependencies` provide explicit selections.

## Development

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
```

Tests use isolated temporary projects, including actual interrupted processes and CLI recovery. A runnable read-only example is in `example/flutter_janitor_example.dart`.

MIT; see `LICENSE`.
