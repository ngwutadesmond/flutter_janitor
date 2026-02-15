import 'dart:io';

import 'package:flutter_janitor/src/pubspec_parser.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('PubspecParser', () {
    test('expands asset directories, explicit entries, and fonts', () async {
      final fixture = await copyFixtureToTemp('sample_project');
      addTearDown(() => fixture.delete(recursive: true));

      final parser = PubspecParser();
      final pubspec = await parser.parse(fixture.path);

      expect(pubspec.declaredAssets, contains('assets/images/used.png'));
      expect(pubspec.declaredAssets, contains('assets/images/unused/old.png'));
      expect(pubspec.declaredAssets, contains('assets/json/config.json'));
      expect(pubspec.declaredAssets, contains('assets/yaml/runtime.yaml'));
      expect(pubspec.declaredAssets, contains('assets/fonts/app_font.ttf'));
      expect(pubspec.declaredAssets, contains('assets/fonts/unused_font.ttf'));

      expect(pubspec.fontFamilies.keys, containsAll(['AppFont', 'UnusedFont']));
      expect(
        pubspec.fontFamilies['AppFont']!.files,
        contains('assets/fonts/app_font.ttf'),
      );
      expect(
        pubspec.fontFamilies['UnusedFont']!.files,
        contains('assets/fonts/unused_font.ttf'),
      );

      expect(
        pubspec.dependencies.keys,
        containsAll(['http', 'provider', 'build_runner']),
      );
      expect(
        pubspec.devDependencies.keys,
        containsAll(['mocktail', 'json_serializable']),
      );
    });

    test('throws when pubspec.yaml is missing', () async {
      final dir = await Directory.systemTemp.createTemp(
        'flutter_janitor_missing_pubspec_',
      );
      addTearDown(() => dir.delete(recursive: true));

      final parser = PubspecParser();
      expect(() => parser.parse(dir.path), throwsStateError);
    });
  });
}
