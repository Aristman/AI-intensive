import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/services/patch_apply_service.dart';

void main() {
  group('PatchApplyService diff-only', () {
    test('applies simple full-file unified diff', () async {
      final dir = await Directory.systemTemp.createTemp('autofix_test_');
      final file = File('${dir.path}/foo.txt');
      await file.writeAsString('old\nold2\n');

      const diff = '--- a/${'REPLACED'}/foo.txt\n'
          '+++ b/${'REPLACED'}/foo.txt\n'
          '@@ -1,2 +1,2 @@\n'
          '-old\n'
          '-old2\n'
          '+new\n'
          '+new2\n';

      final svc = PatchApplyService();
      final applied = await svc.applyPatches([
        {
          'path': file.path,
          'diff': diff,
        }
      ]);

      expect(applied, 1);
      final content = await file.readAsString();
      expect(content, 'new\nnew2\n');

      // rollback
      final rolled = await svc.rollbackLast();
      expect(rolled, 1);
      final content2 = await file.readAsString();
      expect(content2, 'old\nold2\n');
    });

    test('skips unsupported diff gracefully', () async {
      final dir = await Directory.systemTemp.createTemp('autofix_test_');
      final file = File('${dir.path}/bar.txt');
      await file.writeAsString('keep\n');

      // malformed headers
      const diff = '--- x\n+++ y\n@@ -1,1 +1,1 @@\n-keep\n+changed\n';

      final svc = PatchApplyService();
      final applied = await svc.applyPatches([
        {
          'path': file.path,
          'diff': diff,
        }
      ]);

      expect(applied, 0);
      final content = await file.readAsString();
      expect(content, 'keep\n');
    });
  });
}
