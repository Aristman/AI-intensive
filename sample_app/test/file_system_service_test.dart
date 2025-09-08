import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/agents/workspace/file_system_service.dart';

void main() {
  group('FileSystemService', () {
    late Directory tmp;
    late FileSystemService fs;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('fs_svc_test_');
      fs = FileSystemService(tmp.path);
    });

    tearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    test('list empty dir', () async {
      final res = await fs.list('.');
      expect(res.entries, isEmpty);
      expect(res.path, '.');
    });

    test('write then read file (no overwrite by default)', () async {
      final write1 = await fs.writeFile(path: 'a/b.txt', content: 'hello', createDirs: true);
      expect(write1.success, isTrue);

      final read = await fs.readFile('a/b.txt');
      expect(read.exists, isTrue);
      expect(read.size, 5);
      expect(read.contentSnippet.contains('hello'), isTrue);

      final write2 = await fs.writeFile(path: 'a/b.txt', content: 'world', createDirs: true);
      expect(write2.success, isFalse, reason: 'overwrite should be false by default');

      final write3 = await fs.writeFile(path: 'a/b.txt', content: 'world', createDirs: true, overwrite: true);
      expect(write3.success, isTrue);
      final read2 = await fs.readFile('a/b.txt');
      expect(read2.size, 5);
      expect(read2.contentSnippet.contains('world'), isTrue);
    });

    test('delete file and directory (recursive)', () async {
      await fs.writeFile(path: 'dir1/file.txt', content: 'x', createDirs: true, overwrite: true);
      final delFile = await fs.deletePath('dir1/file.txt');
      expect(delFile.success, isTrue);

      await fs.writeFile(path: 'dir2/sub/file.txt', content: 'x', createDirs: true, overwrite: true);
      final delDirFail = await fs.deletePath('dir2');
      expect(delDirFail.success, isFalse, reason: 'non-empty dir requires recursive');

      final delDirOk = await fs.deletePath('dir2', recursive: true);
      expect(delDirOk.success, isTrue);
    });

    test('path traversal is blocked', () async {
      // Создадим за пределами корня файл и попробуем выйти из корня через ..
      final outside = await File('${tmp.parent.path}${Platform.pathSeparator}evil.txt').create(recursive: true);
      await outside.writeAsString('do not read');

      final res = await fs.readFile('../evil.txt');
      expect(res.message.toLowerCase(), contains('ошибка доступа'));
    });
  });
}
