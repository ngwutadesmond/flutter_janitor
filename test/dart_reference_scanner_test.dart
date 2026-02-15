import 'dart:io';

import 'package:flutter_janitor/src/dart_reference_scanner.dart';
import 'package:test/test.dart';

void main() {
  group('DartReferenceScanner', () {
    test('detects direct references and const propagation', () async {
      final dir =
          await Directory.systemTemp.createTemp('flutter_janitor_dart_scan_');
      addTearDown(() => dir.delete(recursive: true));

      final lib = Directory('${dir.path}/lib')..createSync(recursive: true);
      final file = File('${lib.path}/main.dart');
      await file.writeAsString('''
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

const logo = 'assets/images/logo.png';

void main() {
  http.get(Uri.parse('https://example.com'));
  Image.asset('assets/images/used.png');
  Image.asset(logo);
}
''');

      final scanner = DartReferenceScanner();
      final result = await scanner.scanFiles(
        projectRoot: dir.path,
        dartFiles: ['lib/main.dart'],
      );

      expect(result.usedAssets, contains('assets/images/used.png'));
      expect(result.usedAssets, contains('assets/images/logo.png'));
      expect(result.usedPackages, contains('http'));
      expect(result.unsafeAssetPrefixes, isEmpty);
    });

    test('marks dynamic and prefix references as unsafe', () async {
      final dir =
          await Directory.systemTemp.createTemp('flutter_janitor_dart_scan_');
      addTearDown(() => dir.delete(recursive: true));

      final lib = Directory('${dir.path}/lib')..createSync(recursive: true);
      final file = File('${lib.path}/main.dart');
      await file.writeAsString(r'''
const iconPrefix = 'assets/icons/';

void main() {
  Image.asset('${iconPrefix}home.png');
}
''');

      final scanner = DartReferenceScanner();
      final result = await scanner.scanFiles(
        projectRoot: dir.path,
        dartFiles: ['lib/main.dart'],
      );

      expect(result.usedAssets, isEmpty);
      expect(result.unsafeAssetPrefixes, contains('assets/icons/'));
    });
  });
}
