import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/agents/workspace/workspace_fs_agent.dart';

void main() {
  group('WorkspaceFsAgent tools', () {
    late Directory tmp;
    late WorkspaceFsAgent agent;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('fs_agent_test_');
      agent = WorkspaceFsAgent(rootDir: tmp.path);
    });

    tearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    test('fs_write then fs_read', () async {
      final resWrite = await agent.callTool('fs_write', {
        'path': 'notes/hello.txt',
        'content': 'hello world',
        'createDirs': true,
      });
      expect(resWrite['ok'], isTrue);

      final resRead = await agent.callTool('fs_read', {'path': 'notes/hello.txt'});
      expect(resRead['ok'], isTrue);
      expect((resRead['contentSnippet'] as String).contains('hello world'), isTrue);
    });

    test('fs_list and fs_delete', () async {
      await agent.callTool('fs_write', {
        'path': 'a/b/c.txt',
        'content': 'x',
        'createDirs': true,
        'overwrite': true,
      });
      var resList = await agent.callTool('fs_list', {'path': 'a/b'});
      expect(resList['ok'], isTrue);
      final entries = (resList['entries'] as List).cast<Map<String, dynamic>>();
      expect(entries.length, 1);
      expect(entries.first['name'], 'c.txt');
      expect(entries.first['isDir'], isFalse);

      // delete file
      final delFile = await agent.callTool('fs_delete', {'path': 'a/b/c.txt'});
      expect(delFile['ok'], isTrue);

      // create nested and delete recursively
      await agent.callTool('fs_write', {
        'path': 'deep/x/y/z.txt',
        'content': 'z',
        'createDirs': true,
        'overwrite': true,
      });
      final delDirFail = await agent.callTool('fs_delete', {'path': 'deep'});
      expect(delDirFail['ok'], isFalse);

      final delDirOk = await agent.callTool('fs_delete', {'path': 'deep', 'recursive': true});
      expect(delDirOk['ok'], isTrue);
    });

    test('ask() simple parser list/read/write/delete', () async {
      // write
      final r1 = await agent.ask(const AgentRequest('write foo.txt: abc'));
      expect(r1.text.toLowerCase(), contains('записано'));
      // read
      final r2 = await agent.ask(const AgentRequest('read foo.txt'));
      expect(r2.text, contains('Содержимое'));
      // list
      final r3 = await agent.ask(const AgentRequest('list .'));
      expect(r3.text.toLowerCase(), contains('каталог'));
      // delete
      final r4 = await agent.ask(const AgentRequest('delete foo.txt'));
      expect(r4.text.toLowerCase(), contains('удалено'));
    });
  });
}
