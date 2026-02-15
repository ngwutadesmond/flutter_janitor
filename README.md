# flutter_janitor

`flutter_janitor` is a conservative Flutter cleanup CLI that scans for:

- unused declared assets (images/fonts/json/yaml)
- unused declared dependencies/dev_dependencies
- potentially unsafe cleanup candidates (dynamic references, tooling-only package mentions)

It outputs **Markdown (`.md`) or text (`.txt`) reports only** and supports safe cleanup with backup + undo.

## Features

- `scan` mode for read-only analysis
- `clean` mode with dry-run by default
- safe/unsafe buckets to avoid risky automatic deletions
- backup manifest and `undo`
- optional pre/post checks (`pub get`, `analyze`, `test`)

## Installation

```bash
dart pub global activate flutter_janitor
```

Run as:

```bash
flutter_janitor scan
```

## Commands

### Scan

```bash
flutter_janitor scan \
  --format md \
  --output janitor_report.md \
  --include test,integration_test,example \
  --exclude build,.dart_tool,ios,android,macos,windows,linux,web \
  --include-native-scan
```

Outputs groups:

1. Unused assets (safe to remove)
2. Potentially unused assets (unsafe)
3. Unused dependencies (safe)
4. Potentially unused dependencies (unsafe)
5. Missing references (referenced but not declared)
6. Summary + next actions

### Clean

Dry-run preview:

```bash
flutter_janitor clean
```

Apply safe cleanup:

```bash
flutter_janitor clean --apply --yes
```

Interactive apply:

```bash
flutter_janitor clean --apply --interactive
```

Apply with extra verification:

```bash
flutter_janitor clean --apply --yes --run-analyze --run-tests
```

### Undo

```bash
flutter_janitor clean --undo .janitor_backup/manifest_123456.yaml
```

## Safety Model

- Default is dry-run.
- Only **safe buckets** are auto-applied.
- Dynamic or prefix-based asset references are marked **unsafe**.
- Tooling/config-only dependency mentions are marked **unsafe**.
- Deleted assets are moved to backup (not hard-deleted).
- `pubspec.yaml` is backed up before dependency removal.

## Asset Detection

Supports declared assets/fonts from `pubspec.yaml`:

- images: `svg`, `png`, `jpeg`, `jpg`, `webp`
- fonts: declared in `flutter/fonts` + font files
- data/config: `json`, `yaml`, `yml` (when declared under `flutter/assets`)

Dart usage patterns scanned:

- `AssetImage(...)`
- `Image.asset(...)`
- `SvgPicture.asset(...)`
- `Lottie.asset(...)` (best effort)
- `rootBundle.loadString/load(...)`
- `DefaultAssetBundle.of(context).loadString/load(...)`
- simple const propagation in file (`const a = 'assets/x.png'` then `Image.asset(a)`)

## Dependency Detection

Uses Dart `import`/`export` package usage:

- `import 'package:xyz/...';`
- `export 'package:xyz/...';`

Protected packages are never auto-removed:

- `flutter`
- `flutter_test`
- `cupertino_icons`

Tooling/config references (for example in `build.yaml`) move dependencies to the unsafe bucket.

## Limitations

- Dynamic asset paths are intentionally conservative and can increase unsafe buckets.
- Dependency usage from external scripts/build systems may be ambiguous.
- Native scan (`--include-native-scan`) is best-effort string matching.

## Development

```bash
dart pub get
dart format --set-exit-if-changed .
dart analyze
dart test
```

## License

MIT, see `LICENSE`.
