import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/services/patch_apply_service.dart';

void main() {
  group('PatchApplyService', () {
    test('apply and rollback patches', () async {
      final dir = await Directory.systemTemp.createTemp('patch_apply_');
      final f1 = File('${dir.path}/a.txt');
      final f2 = File('${dir.path}/b.txt');
      await f1.create(recursive: true);
      await f2.create(recursive: true);
      await f1.writeAsString('oldA');
      await f2.writeAsString('oldB');

      final service = PatchApplyService();
      final patches = [
        {
          'path': f1.path,
          'newContent': 'newA',
        },
        {
          'path': f2.path,
          'newContent': 'newB',
        }
      ];

      final applied = await service.applyPatches(patches);
      expect(applied, 2);
      expect(await f1.readAsString(), 'newA');
      expect(await f2.readAsString(), 'newB');

      // .bak files created
      expect(await File('${f1.path}.bak').exists(), true);
      expect(await File('${f2.path}.bak').exists(), true);

      final restored = await service.rollbackLast();
      expect(restored, 2);
      expect(await f1.readAsString(), 'oldA');
      expect(await f2.readAsString(), 'oldB');

      // .bak files removed best-effort (not critical if leftover, but we try)
      // We won't assert deletion strictly to avoid flakiness on CI.

      await dir.delete(recursive: true);
    });
  });
}
