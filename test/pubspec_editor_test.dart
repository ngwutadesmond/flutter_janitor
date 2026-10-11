import 'package:flutter_janitor/src/models.dart';
import 'package:flutter_janitor/src/pubspec_editor.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const remove = CleanActionPlan(
    assetPaths: {'logo.png'},
    removeDependencies: {'drop'},
    removeDevDependencies: {'dev_drop'});
void main() {
  for (final style in ['block', 'inline', 'quoted', 'crlf', 'indent']) {
    test('semantic edit preserves unrelated YAML ($style)', () {
      var original = '''
# preserve this comment
name: demo
description: keeps scalar fields after dependencies
dependencies:
  drop: ^1.0.0
  keep:
    path: ../local
homepage: https://example.invalid
dev_dependencies:
  dev_drop: ^2.0.0
  dev_keep: any
flutter:
  assets:
    - logo.png
    - images/
  uses-material-design: true
custom:
  deeply: [a, b]
''';
      if (style == 'inline') {
        original = original
            .replaceFirst('  drop: ^1.0.0\n  keep:\n    path: ../local',
                '  drop: ^1.0.0\n  keep: {path: ../local}')
            .replaceFirst(
                'dependencies:\n  drop: ^1.0.0\n  keep: {path: ../local}',
                'dependencies: {drop: ^1.0.0, keep: {path: ../local}}');
      }
      if (style == 'quoted') {
        original = original
            .replaceAll('drop:', '"drop":')
            .replaceAll('dev_"drop":', '"dev_drop":');
      }
      if (style == 'crlf') original = original.replaceAll('\n', '\r\n');
      if (style == 'indent') {
        original = original
            .replaceAll('\n  ', '\n    ')
            .replaceAll('\n      path:', '\n        path:');
      }
      final updated = PubspecEditor().edit(original, remove);
      final yaml = loadYaml(updated);
      expect(yaml['dependencies'].keys.toList(), ['keep']);
      expect(yaml['dependencies']['keep']['path'], '../local');
      expect(yaml['dev_dependencies'].keys.toList(), ['dev_keep']);
      expect(yaml['homepage'], 'https://example.invalid');
      expect(yaml['flutter']['assets'], ['images/']);
      expect(yaml['flutter']['uses-material-design'], true);
      expect(yaml['custom']['deeply'], ['a', 'b']);
      expect(updated, contains('# preserve this comment'));
      if (style == 'crlf') {
        expect(updated.replaceAll('\r\n', '').contains('\n'), false);
      }
    });
  }
  test('aliases that would affect unrelated sections are rejected or preserved',
      () {
    const yaml = '''
name: demo
dependencies: &deps
  drop: any
  keep: any
custom: *deps
''';
    try {
      final updated = PubspecEditor().edit(
          yaml,
          const CleanActionPlan(
              assetPaths: {},
              removeDependencies: {'drop'},
              removeDevDependencies: {}));
      expect(loadYaml(updated)['custom']['drop'], 'any');
      expect(loadYaml(updated)['dependencies'].containsKey('drop'), false);
    } on FormatException catch (error) {
      expect(error.message, contains('alias'));
    } on StateError catch (error) {
      expect(error.message, contains('semantics'));
    }
  });
  test('missing dependency and protected configured asset reject edit', () {
    expect(
        () => PubspecEditor().edit('name: demo\n', remove), throwsStateError);
    expect(
        () => PubspecEditor().edit(
            'name: demo\nflutter:\n  assets:\n    - path: logo.png\n      flavors: [a]\n',
            const CleanActionPlan(
                assetPaths: {'logo.png'},
                removeDependencies: {},
                removeDevDependencies: {})),
        throwsStateError);
  });
}
