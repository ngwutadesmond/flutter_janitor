import 'package:flutter_janitor/src/path_utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final windows = p.Context(style: p.Style.windows);
  test('Windows-generated operation, backup and journal paths are portable',
      () {
    for (final path in [
      r'C:\consumer\.janitor_backup',
      r'C:\consumer\.janitor_backup\operation-one',
      r'C:\consumer\.janitor_backup\operation-one\manifest.json',
    ]) {
      final relative =
          portableRelativePath(path, from: r'C:\consumer', context: windows);
      expect(relative, startsWith('.janitor_backup'));
      expect(relative, isNot(contains(r'\')));
      expect(relative, isNot(contains('..')));
    }
  });
  test('normalization retains external sibling traversal for rejection', () {
    final relative = portableRelativePath(r'C:\consumer-other\backup',
        from: r'C:\consumer', context: windows);
    expect(relative, '../consumer-other/backup');
    expect(() => checkedPath('/tmp/consumer', relative), throwsStateError);
    expect(() => checkedPath('/tmp/consumer', r'assets\remove.png'),
        throwsStateError);
  });
}
