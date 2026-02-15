import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';
import 'path_utils.dart';
import 'pubspec_parser.dart';

class DartReferenceScanner {
  static final RegExp _constStringRegex = RegExp(
    r'''(?:static\s+)?const\s+(?:String\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*r?["']([^"']+)["']\s*;''',
    multiLine: true,
  );

  static final RegExp _assetCallRegex = RegExp(
    r'''(AssetImage|Image\.asset|SvgPicture\.asset|Lottie\.asset|rootBundle\.loadString|rootBundle\.load|DefaultAssetBundle\.of\([^\)]*\)\.loadString|DefaultAssetBundle\.of\([^\)]*\)\.load)\s*\(([^\)]*)\)''',
    multiLine: true,
    dotAll: true,
  );

  static final RegExp _stringLiteralRegex = RegExp(r'''r?["']([^"']+)["']''');

  static final RegExp _fontFamilyRegex = RegExp(
    r'''fontFamily\s*:\s*r?["']([^"']+)["']''',
  );

  static final RegExp _packageImportRegex = RegExp(
    r'''(?:import|export)\s+r?["']package:([a-zA-Z0-9_]+)\/''',
    multiLine: true,
  );
  static final RegExp _interpolationVariableRegex = RegExp(
    r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}',
  );
  static final RegExp _dollarVariableRegex = RegExp(
    r'\$([A-Za-z_][A-Za-z0-9_]*)',
  );

  Future<DartReferenceScanResult> scanFiles({
    required String projectRoot,
    required List<String> dartFiles,
  }) async {
    final result = DartReferenceScanResult();

    for (final relPath in dartFiles) {
      final file = File(p.join(projectRoot, relPath));
      if (!await file.exists()) {
        continue;
      }
      final content = await file.readAsString();
      _scanFile(content, result);
    }

    return result;
  }

  void _scanFile(String content, DartReferenceScanResult result) {
    final constants = <String, String>{};

    for (final match in _constStringRegex.allMatches(content)) {
      final name = match.group(1)!;
      final value = normalizePath(match.group(2)!);
      constants[name] = value;
    }

    for (final match in _assetCallRegex.allMatches(content)) {
      final rawArguments = match.group(2) ?? '';
      final expression = _firstArgument(rawArguments).trim();
      if (expression.isEmpty) {
        continue;
      }
      _resolveAssetExpression(expression, constants, result);
    }

    for (final match in _fontFamilyRegex.allMatches(content)) {
      final family = match.group(1);
      if (family != null && family.trim().isNotEmpty) {
        result.usedFontFamilies.add(family.trim());
      }
    }

    for (final match in _packageImportRegex.allMatches(content)) {
      final packageName = match.group(1);
      if (packageName != null && packageName.isNotEmpty) {
        result.usedPackages.add(packageName);
      }
    }
  }

  String _firstArgument(String args) {
    var quote = '';
    var parenDepth = 0;
    for (var i = 0; i < args.length; i++) {
      final ch = args[i];
      if (quote.isNotEmpty) {
        if (ch == quote && (i == 0 || args[i - 1] != '\\')) {
          quote = '';
        }
        continue;
      }
      if (ch == '\'' || ch == '"') {
        quote = ch;
        continue;
      }
      if (ch == '(' || ch == '[' || ch == '{') {
        parenDepth++;
        continue;
      }
      if (ch == ')' || ch == ']' || ch == '}') {
        if (parenDepth > 0) {
          parenDepth--;
        }
        continue;
      }
      if (ch == ',' && parenDepth == 0) {
        return args.substring(0, i);
      }
    }
    return args;
  }

  void _resolveAssetExpression(
    String expression,
    Map<String, String> constants,
    DartReferenceScanResult result,
  ) {
    final value = expression.trim();

    if (value.contains(r'${') || value.contains('+')) {
      _extractUnsafePrefixes(value, constants, result);
      return;
    }

    final stringLiteral = _extractStringLiteral(value);
    if (stringLiteral != null) {
      if (_looksLikeAssetPath(stringLiteral)) {
        result.usedAssets.add(normalizePath(stringLiteral));
        return;
      }
      if (_looksLikeAssetPrefix(stringLiteral)) {
        result.unsafeAssetPrefixes.add(ensureTrailingSlash(stringLiteral));
      }
      return;
    }

    if (constants.containsKey(value)) {
      final constantValue = constants[value]!;
      if (_looksLikeAssetPath(constantValue)) {
        result.usedAssets.add(normalizePath(constantValue));
      } else if (_looksLikeAssetPrefix(constantValue)) {
        result.unsafeAssetPrefixes.add(ensureTrailingSlash(constantValue));
      }
      return;
    }

    if (_looksLikeAssetPrefix(value)) {
      result.unsafeAssetPrefixes.add(ensureTrailingSlash(value));
    }
  }

  void _extractUnsafePrefixes(
    String expression,
    Map<String, String> constants,
    DartReferenceScanResult result,
  ) {
    for (final match in _interpolationVariableRegex.allMatches(expression)) {
      final variable = match.group(1);
      if (variable == null) {
        continue;
      }
      final value = constants[variable];
      if (value == null) {
        continue;
      }
      if (_looksLikeAssetPrefix(value)) {
        result.unsafeAssetPrefixes.add(ensureTrailingSlash(value));
      } else if (_looksLikeAssetPath(value)) {
        result.unsafeAssetPrefixes.add(ensureTrailingSlash(p.dirname(value)));
      }
    }

    for (final match in _dollarVariableRegex.allMatches(expression)) {
      final variable = match.group(1);
      if (variable == null) {
        continue;
      }
      final value = constants[variable];
      if (value == null) {
        continue;
      }
      if (_looksLikeAssetPrefix(value)) {
        result.unsafeAssetPrefixes.add(ensureTrailingSlash(value));
      } else if (_looksLikeAssetPath(value)) {
        result.unsafeAssetPrefixes.add(ensureTrailingSlash(p.dirname(value)));
      }
    }

    final literals = _stringLiteralRegex
        .allMatches(expression)
        .map((match) => normalizePath(match.group(1)!))
        .toList();

    var added = false;
    for (final literal in literals) {
      if (_looksLikeAssetPrefix(literal)) {
        result.unsafeAssetPrefixes.add(ensureTrailingSlash(literal));
        added = true;
      } else if (_looksLikeAssetPath(literal)) {
        final prefix = p.dirname(literal);
        if (prefix != '.') {
          result.unsafeAssetPrefixes.add(ensureTrailingSlash(prefix));
          added = true;
        }
      }
    }

    if (!added && expression.contains('assets/')) {
      result.unsafeAssetPrefixes.add('assets/');
    }
  }

  String? _extractStringLiteral(String expression) {
    final value = expression.trim();
    if (value.length < 2) {
      return null;
    }

    final hasRawPrefix = value.startsWith('r\'') || value.startsWith('r"');
    final start = hasRawPrefix ? 1 : 0;
    if (value.length <= start + 1) {
      return null;
    }

    final quote = value[start];
    if ((quote != '\'' && quote != '"') || value[value.length - 1] != quote) {
      return null;
    }

    return normalizePath(value.substring(start + 1, value.length - 1));
  }

  bool _looksLikeAssetPath(String value) {
    final normalized = normalizePath(value);
    if (!normalized.contains('/')) {
      return false;
    }
    final extension = p.extension(normalized).toLowerCase();
    if (extension.isEmpty) {
      return false;
    }
    return PubspecParser.supportedAssetExtensions.contains(extension);
  }

  bool _looksLikeAssetPrefix(String value) {
    final normalized = normalizePath(value);
    if (!normalized.contains('/')) {
      return false;
    }
    return p.extension(normalized).isEmpty || normalized.endsWith('/');
  }
}
