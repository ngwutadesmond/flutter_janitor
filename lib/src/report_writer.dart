import 'models.dart';

/// Converts scan/clean results into human-friendly Markdown or plain text.
class ReportWriter {
  /// Renders a scan report.
  String renderScan(JanitorScanResult result, {required ReportFormat format}) {
    return format == ReportFormat.md
        ? _renderScanMarkdown(result)
        : _renderScanText(result);
  }

  /// Renders a clean report with scan details and clean execution summary.
  String renderClean(
    CleanExecutionResult result, {
    required ReportFormat format,
  }) {
    final scanReport = renderScan(result.scanResult, format: format);
    if (format == ReportFormat.md) {
      return _renderCleanMarkdown(result, scanReport);
    }
    return _renderCleanText(result, scanReport);
  }

  String _renderScanMarkdown(JanitorScanResult result) {
    final asset = result.assetAnalysis;
    final dependency = result.dependencyAnalysis;

    final buffer = StringBuffer()
      ..writeln('# Flutter Janitor Report')
      ..writeln()
      ..writeln('## 1) Unused Assets (Safe to Remove)')
      ..writeln(_markdownPathTable(asset.unusedSafe))
      ..writeln('## 2) Potentially Unused Assets (Unsafe Bucket)')
      ..writeln(
        _markdownUnsafeAssetTable(asset.unusedUnsafe, asset.unsafePrefixes),
      )
      ..writeln('## 3) Unused Dependencies (Safe)')
      ..writeln(_markdownDependencyTable(dependency.unusedSafe, const {}))
      ..writeln('## 4) Potentially Unused Dependencies (Unsafe Bucket)')
      ..writeln(
        _markdownDependencyTable(
          dependency.unusedUnsafe,
          dependency.unsafeReasons,
        ),
      )
      ..writeln('## 5) Missing References (Referenced but not Declared)')
      ..writeln(_markdownPathTable(asset.missingReferences))
      ..writeln('## 6) Summary and Next Actions')
      ..writeln(
        '- Declared assets: **${result.declaredAssetCount}**  \\n'
        '- Safe unused assets: **${asset.unusedSafe.length}**  \\n'
        '- Unsafe assets: **${asset.unusedUnsafe.length}**  \\n'
        '- Safe unused dependencies: **${dependency.unusedSafe.length}**  \\n'
        '- Unsafe dependencies: **${dependency.unusedUnsafe.length}**',
      )
      ..writeln()
      ..writeln('Next actions:')
      ..writeln('- Run `flutter_janitor clean` to preview cleanup plan.')
      ..writeln(
        '- Run `flutter_janitor clean --apply` to apply safe cleanup with backup + undo manifest.',
      );

    return buffer.toString().trimRight();
  }

  String _renderScanText(JanitorScanResult result) {
    final asset = result.assetAnalysis;
    final dependency = result.dependencyAnalysis;

    final buffer = StringBuffer()
      ..writeln('FLUTTER JANITOR REPORT')
      ..writeln('=====================')
      ..writeln()
      ..writeln('1) Unused assets (safe to remove)')
      ..writeln(_textPathList(asset.unusedSafe))
      ..writeln()
      ..writeln('2) Potentially unused assets (unsafe bucket)')
      ..writeln(_textUnsafeAssetList(asset.unusedUnsafe, asset.unsafePrefixes))
      ..writeln()
      ..writeln('3) Unused dependencies (safe)')
      ..writeln(_textDependencyList(dependency.unusedSafe, const {}))
      ..writeln()
      ..writeln('4) Potentially unused dependencies (unsafe bucket)')
      ..writeln(
        _textDependencyList(dependency.unusedUnsafe, dependency.unsafeReasons),
      )
      ..writeln()
      ..writeln('5) Missing references (referenced but not declared)')
      ..writeln(_textPathList(asset.missingReferences))
      ..writeln()
      ..writeln('6) Summary + next actions')
      ..writeln('Declared assets: ${result.declaredAssetCount}')
      ..writeln('Safe unused assets: ${asset.unusedSafe.length}')
      ..writeln('Unsafe assets: ${asset.unusedUnsafe.length}')
      ..writeln('Safe unused dependencies: ${dependency.unusedSafe.length}')
      ..writeln('Unsafe dependencies: ${dependency.unusedUnsafe.length}')
      ..writeln(
        'Next: run `flutter_janitor clean` for dry-run, then `flutter_janitor clean --apply` to apply safe changes.',
      );

    return buffer.toString().trimRight();
  }

  String _renderCleanMarkdown(CleanExecutionResult result, String scanReport) {
    final buffer = StringBuffer()
      ..writeln(scanReport)
      ..writeln()
      ..writeln('## Clean Execution')
      ..writeln('- Applied: **${result.applied ? 'yes' : 'no'}**')
      ..writeln('- Assets planned: **${result.plan.assetPaths.length}**')
      ..writeln(
        '- Dependencies planned: **${result.plan.removeDependencies.length + result.plan.removeDevDependencies.length}**',
      );

    if (result.manifest != null) {
      buffer.writeln('- Manifest: `${result.manifest!.manifestPath}`');
    }

    if (result.preflight.isNotEmpty) {
      buffer.writeln(
        '- Preflight checks: ${_formatRunResultSummary(result.preflight)}',
      );
    }
    if (result.postflight.isNotEmpty) {
      buffer.writeln(
        '- Postflight checks: ${_formatRunResultSummary(result.postflight)}',
      );
    }
    if (result.messages.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Notes:');
      for (final message in result.messages) {
        buffer.writeln('- $message');
      }
    }

    return buffer.toString().trimRight();
  }

  String _renderCleanText(CleanExecutionResult result, String scanReport) {
    final buffer = StringBuffer()
      ..writeln(scanReport)
      ..writeln()
      ..writeln('CLEAN EXECUTION')
      ..writeln('---------------')
      ..writeln('Applied: ${result.applied ? 'yes' : 'no'}')
      ..writeln('Assets planned: ${result.plan.assetPaths.length}')
      ..writeln(
        'Dependencies planned: ${result.plan.removeDependencies.length + result.plan.removeDevDependencies.length}',
      );

    if (result.manifest != null) {
      buffer.writeln('Manifest: ${result.manifest!.manifestPath}');
    }

    if (result.preflight.isNotEmpty) {
      buffer.writeln(
        'Preflight checks: ${_formatRunResultSummary(result.preflight)}',
      );
    }
    if (result.postflight.isNotEmpty) {
      buffer.writeln(
        'Postflight checks: ${_formatRunResultSummary(result.postflight)}',
      );
    }
    for (final message in result.messages) {
      buffer.writeln('Note: $message');
    }

    return buffer.toString().trimRight();
  }

  String _markdownPathTable(Set<String> values) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) {
      return '_None_\n';
    }

    final buffer = StringBuffer()
      ..writeln('| Path |')
      ..writeln('| --- |');
    for (final path in sorted) {
      buffer.writeln('| `$path` |');
    }
    return '${buffer.toString()}\n';
  }

  String _markdownUnsafeAssetTable(Set<String> values, Set<String> prefixes) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) {
      return '_None_\n';
    }

    final sortedPrefixes = prefixes.toList()..sort();
    final prefixText = sortedPrefixes.isEmpty
        ? 'dynamic/prefix reference detected'
        : 'matches unsafe prefix: ${sortedPrefixes.join(', ')}';

    final buffer = StringBuffer()
      ..writeln('| Path | Reason |')
      ..writeln('| --- | --- |');
    for (final path in sorted) {
      buffer.writeln('| `$path` | $prefixText |');
    }
    return '${buffer.toString()}\n';
  }

  String _markdownDependencyTable(
    Set<String> values,
    Map<String, String> reasons,
  ) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) {
      return '_None_\n';
    }

    final buffer = StringBuffer()
      ..writeln('| Dependency | Reason |')
      ..writeln('| --- | --- |');
    for (final name in sorted) {
      final reason = reasons[name] ?? 'No usage imports detected.';
      buffer.writeln('| `$name` | $reason |');
    }
    return '${buffer.toString()}\n';
  }

  String _textPathList(Set<String> values) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) {
      return '  - none';
    }
    return sorted.map((entry) => '  - $entry').join('\n');
  }

  String _textUnsafeAssetList(Set<String> values, Set<String> prefixes) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) {
      return '  - none';
    }

    final prefixText = prefixes.isEmpty
        ? ''
        : ' (unsafe prefixes: ${prefixes.toList()..sort()})';
    return sorted.map((entry) => '  - $entry$prefixText').join('\n');
  }

  String _textDependencyList(Set<String> values, Map<String, String> reasons) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) {
      return '  - none';
    }
    return sorted
        .map(
          (entry) =>
              '  - $entry${reasons.containsKey(entry) ? ' (${reasons[entry]})' : ''}',
        )
        .join('\n');
  }

  String _formatRunResultSummary(List<RunResult> results) {
    return results
        .map((entry) => '${entry.command}: ${entry.success ? 'ok' : 'failed'}')
        .join(', ');
  }
}
