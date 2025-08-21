import 'package:test/test.dart';
import 'package:sample_app/utils/code_utils.dart';

void main() {
  group('stripCodeFencesGlobal', () {
    test('keeps plain text', () {
      const input = 'class A {}';
      expect(stripCodeFencesGlobal(input), 'class A {}');
    });

    test('removes fenced with language header', () {
      const input = '```java\nclass A {}\n```';
      expect(stripCodeFencesGlobal(input), 'class A {}');
    });

    test('removes fenced without language header', () {
      const input = '```\nclass A {}\n```';
      expect(stripCodeFencesGlobal(input), 'class A {}');
    });
  });

  group('inferPackageName / inferPublicClassName', () {
    test('extracts package and class', () {
      const code = 'package com.example;\npublic class App {}';
      expect(inferPackageName(code), 'com.example');
      expect(inferPublicClassName(code), 'App');
    });

    test('no package returns null', () {
      const code = 'public class Main {}';
      expect(inferPackageName(code), isNull);
      expect(inferPublicClassName(code), 'Main');
    });
  });

  group('basenameNoExt', () {
    test('unix path', () {
      expect(basenameNoExt('com/example/App.java'), 'App');
    });
    test('windows path', () {
      expect(basenameNoExt('com\\example\\App.java'), 'App');
    });
    test('no ext', () {
      expect(basenameNoExt('App'), 'App');
    });
  });

  group('fqcnFromFile', () {
    test('with package', () {
      final f = {
        'path': 'com/example/App.java',
        'content': 'package com.example;\npublic class App {}',
      };
      expect(fqcnFromFile(f), 'com.example.App');
    });

    test('without package', () {
      final f = {
        'path': 'App.java',
        'content': 'public class App {}',
      };
      expect(fqcnFromFile(f), 'App');
    });
  });

  group('isTestContent / isTestFile', () {
    test('detects junit by import', () {
      const code = 'import org.junit.Test;\npublic class AppTest {}';
      expect(isTestContent(code), isTrue);
    });

    test('detects junit by annotation', () {
      const code = 'public class AppTest { @Test public void x(){} }';
      expect(isTestContent(code), isTrue);
    });

    test('detects by filename suffix', () {
      final f = {
        'path': 'com/example/AppTest.java',
        'content': 'public class AppTest {}',
      };
      expect(isTestFile(f), isTrue);
    });

    test('non-test file', () {
      final f = {
        'path': 'com/example/App.java',
        'content': 'public class App {}',
      };
      expect(isTestFile(f), isFalse);
    });
  });

  group('collectTestDeps', () {
    test('collects test and paired source, returns test fqcn as entrypoint', () {
      final pending = <Map<String, String>>[
        {
          'path': 'com/example/Calculator.java',
          'content': 'package com.example;\npublic class Calculator { public int mul(int a,int b){return a*b;} }',
        },
        {
          'path': 'com/example/CalculatorTest.java',
          'content': 'package com.example;\nimport org.junit.*;\npublic class CalculatorTest { @Test public void t(){ new Calculator(); } }',
        },
      ];
      final testFile = pending[1];
      final out = collectTestDeps(testFile: testFile, pendingFiles: pending);
      final files = (out['files'] as List).cast<Map<String, String>>();
      final entry = out['entrypoint'] as String;
      expect(files.length, 2);
      expect(entry, 'com.example.CalculatorTest');
      expect(files.any((f) => f['path']!.endsWith('Calculator.java')), isTrue);
      expect(files.any((f) => f['path']!.endsWith('CalculatorTest.java')), isTrue);
    });

    test('falls back to only test if source not found', () {
      final pending = <Map<String, String>>[
        {
          'path': 'com/example/CalcTest.java',
          'content': 'package com.example;\nimport org.junit.*;\npublic class CalcTest { @Test public void t(){} }',
        },
      ];
      final out = collectTestDeps(testFile: pending.first, pendingFiles: pending);
      final files = (out['files'] as List).cast<Map<String, String>>();
      final entry = out['entrypoint'] as String;
      expect(files.length, 1);
      expect(entry, 'com.example.CalcTest');
    });
  });
}
