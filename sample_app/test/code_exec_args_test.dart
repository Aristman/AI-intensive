import 'package:test/test.dart';
import 'package:sample_app/agents/code_exec_args.dart';

void main() {
  group('buildDockerExecJavaArgs', () {
    test('returns defaults when only code is provided', () {
      final args = buildDockerExecJavaArgs(code: 'class Main { public static void main(String[] a){} }');

      expect(args['filename'], equals('Main.java'));
      expect(args['code'], contains('class Main'));
      expect(args['timeout_ms'], equals(15000));
      expect(args['cleanup'], equals('always'));
      expect(args['workdir'], equals('/work'));
      expect(args.containsKey('entrypoint'), isFalse);
      expect(args.containsKey('limits'), isFalse);
    });

    test('includes optional fields when provided', () {
      final args = buildDockerExecJavaArgs(
        code: 'class App { public static void main(String[] a){} }',
        filename: 'App.java',
        entrypoint: 'App',
        classpath: 'lib/*:.',
        compileArgs: ['-Xlint:deprecation'],
        runArgs: ['arg1', 'arg2'],
        image: 'eclipse-temurin:17-jdk',
        containerName: 'java-runner',
        extraArgs: '--network=none',
        workdir: '/workspace',
        timeoutMs: 20000,
        cpus: 1,
        memory: '256m',
        cleanup: 'on_success',
      );

      expect(args['filename'], equals('App.java'));
      expect(args['entrypoint'], equals('App'));
      expect(args['classpath'], equals('lib/*:.'));
      expect(args['compile_args'], contains('-Xlint:deprecation'));
      expect(args['run_args'], equals(['arg1', 'arg2']));
      expect(args['image'], equals('eclipse-temurin:17-jdk'));
      expect(args['container_name'], equals('java-runner'));
      expect(args['extra_args'], equals('--network=none'));
      expect(args['workdir'], equals('/workspace'));
      expect(args['timeout_ms'], equals(20000));
      expect(args['cleanup'], equals('on_success'));
      expect(args['limits'], isA<Map<String, dynamic>>());
      final limits = args['limits'] as Map<String, dynamic>;
      expect(limits['cpus'], equals(1));
      expect(limits['memory'], equals('256m'));
    });

    test('infers class and entrypoint when public class present', () {
      final args = buildDockerExecJavaArgs(
        code: 'public class App { public static void main(String[] a){} }',
      );

      expect(args['filename'], equals('App.java'));
      expect(args['entrypoint'], equals('App'));
    });

    test('infers package path in filename and FQCN entrypoint', () {
      final code = 'package com.example.demo;\npublic class Hello { public static void main(String[] a){} }';
      final args = buildDockerExecJavaArgs(
        code: code,
      );

      expect(args['filename'], equals('com/example/demo/Hello.java'));
      expect(args['entrypoint'], equals('com.example.demo.Hello'));
    });

    test('overrides entrypoint "main" with inferred class/FQCN', () {
      final code = 'package x.y;\npublic class Start { public static void main(String[] a){} }';
      final args = buildDockerExecJavaArgs(
        code: code,
        entrypoint: 'main',
      );

      expect(args['filename'], equals('x/y/Start.java'));
      expect(args['entrypoint'], equals('x.y.Start'));
    });
  });
}
