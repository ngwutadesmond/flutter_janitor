# Publishing Guide (pub.dev)

## 1. Prepare release

1. Update version in `pubspec.yaml`.
2. Add release notes in `CHANGELOG.md`.
3. Run checks:

```bash
dart pub get
dart format --set-exit-if-changed .
dart analyze
dart test
```

## 2. Dry run

```bash
dart pub publish --dry-run
```

Address all warnings before publish.

## 3. Publish

```bash
dart pub publish
```

## 4. Versioning strategy

- Use semver (`MAJOR.MINOR.PATCH`).
- `PATCH`: bug fixes and non-breaking safety improvements.
- `MINOR`: additive features/flags with backward compatibility.
- `MAJOR`: breaking CLI behavior/flags or report contract changes.

## 5. pub.dev score tips

- Keep `README.md` complete with usage examples.
- Keep `LICENSE` and `CHANGELOG.md` updated.
- Maintain passing `dart analyze` and tests.
- Prefer stable APIs and deterministic output.
