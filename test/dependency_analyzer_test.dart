import 'package:flutter_janitor/src/dependency_analyzer.dart';
import 'package:flutter_janitor/src/models.dart';
import 'package:test/test.dart';

void main() {
  test('classifies used, unused safe, and potentially unused dependencies', () {
    final analyzer = DependencyAnalyzer();
    final pubspec = PubspecData(
      projectRoot: '/tmp/project',
      pubspecPath: '/tmp/project/pubspec.yaml',
      declaredAssets: const {},
      fontFamilies: const {},
      dependencies: const {
        'flutter': 'sdk:flutter',
        'http': '^1.2.0',
        'provider': '^6.0.0',
        'build_runner': '^2.4.0',
      },
      devDependencies: const {
        'flutter_test': 'sdk:flutter',
        'mocktail': '^1.0.0',
      },
    );

    final references = DartReferenceScanResult(
      usedPackages: {'http', 'mocktail'},
    );
    final toolingHits = {
      'build_runner': {'build.yaml'},
    };

    final result = analyzer.analyze(
      pubspec: pubspec,
      references: references,
      toolingHits: toolingHits,
    );

    expect(result.protected, containsAll(['flutter', 'flutter_test']));
    expect(result.used, containsAll(['http', 'mocktail']));
    expect(result.unusedSafe, contains('provider'));
    expect(result.unusedUnsafe, contains('build_runner'));
    expect(
      result.unsafeReasons['build_runner'],
      contains('Referenced in tooling/config files'),
    );
  });
}
