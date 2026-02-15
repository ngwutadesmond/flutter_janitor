import 'package:flutter_janitor/flutter_janitor.dart';

Future<void> main() async {
  final engine = JanitorEngine();
  final writer = ReportWriter();

  // Run this example from inside a Flutter project directory.
  final result = await engine.scan(
    projectRoot: '.',
    options: const ScanOptions(format: ReportFormat.text),
  );

  final report = writer.renderScan(result, format: ReportFormat.text);
  print(report);
}
