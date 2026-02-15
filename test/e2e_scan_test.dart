import 'package:flutter_janitor/flutter_janitor.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('E2E scan fixture', () {
    test('produces expected markdown and text report content', () async {
      final fixture = await copyFixtureToTemp('sample_project');
      addTearDown(() => fixture.delete(recursive: true));

      final engine = JanitorEngine();
      final writer = ReportWriter();

      final scan = await engine.scan(
        projectRoot: fixture.path,
        options: const ScanOptions(includeNativeScan: false),
      );

      expect(
        scan.assetAnalysis.unusedSafe,
        contains('assets/images/unused/old.png'),
      );
      expect(
        scan.assetAnalysis.unusedUnsafe,
        contains('assets/images/icons/home.png'),
      );
      expect(
        scan.assetAnalysis.unusedUnsafe,
        contains('assets/images/icons/settings.png'),
      );
      expect(
        scan.assetAnalysis.missingReferences,
        contains('assets/yaml/missing_runtime.yaml'),
      );

      expect(scan.dependencyAnalysis.unusedSafe, contains('provider'));
      expect(
        scan.dependencyAnalysis.unusedUnsafe,
        containsAll(['build_runner', 'json_serializable']),
      );

      final markdown = writer.renderScan(scan, format: ReportFormat.md);
      expect(markdown, contains('## 1) Unused Assets (Safe to Remove)'));
      expect(markdown, contains('`assets/images/unused/old.png`'));
      expect(markdown, contains('`provider`'));
      expect(markdown, contains('`build_runner`'));

      final text = writer.renderScan(scan, format: ReportFormat.text);
      expect(text, contains('1) Unused assets (safe to remove)'));
      expect(text, contains('assets/images/unused/old.png'));
      expect(text, contains('Potentially unused dependencies (unsafe bucket)'));
    });
  });
}
