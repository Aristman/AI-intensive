import 'package:test/test.dart';
import 'package:sample_app/agents/code_ops_builder_agent.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/agents/code_ops_agent.dart';
import 'package:sample_app/models/app_settings.dart';

void main() {
  group('CodeOpsBuilderAgent basics', () {
    test('capabilities and tools', () {
      final agent = CodeOpsBuilderAgent(baseSettings: const AppSettings());
      final caps = agent.capabilities;
      expect(caps.stateful, isTrue);
      expect(caps.streaming, isTrue);
      expect(caps.reasoning, isTrue);
      expect(caps.tools, containsAll(['docker_exec_java', 'docker_start_java']));

      expect(agent, isA<IToolingAgent>());
      expect(agent.supportsTool('docker_exec_java'), isTrue);
      expect(agent.supportsTool('docker_start_java'), isTrue);
      expect(agent.supportsTool('unknown_tool'), isFalse);
    });

    test('docker_exec_java guard through callTool when MCP disabled', () async {
      final agent = CodeOpsBuilderAgent(
        baseSettings: const AppSettings(
          useMcpServer: false,
          mcpServerUrl: null,
        ),
      );

      await expectLater(
        agent.callTool('docker_exec_java', {
          'code': 'public class A { public static void main(String[] a){} }',
          'filename': 'A.java',
        }),
        throwsA(isA<StateError>()),
      );
    });

    test('docker_exec_java files guard through callTool when MCP disabled', () async {
      final agent = CodeOpsBuilderAgent(
        baseSettings: const AppSettings(
          useMcpServer: false,
          mcpServerUrl: null,
        ),
      );

      final files = [
        {'path': 'A.java', 'content': 'public class A { public static void main(String[] a){} }'},
      ];

      await expectLater(
        agent.callTool('docker_exec_java', {'files': files}),
        throwsA(isA<StateError>()),
      );
    });

    // Streaming is supported; do not call start() here to avoid network calls.
  });

  group('CodeOpsBuilderAgent orchestration', () {
    test('ask() filters out test files from generated code and asks to create tests', () async {
      final fake = _FakeCodeOpsAgent();
      final agent = CodeOpsBuilderAgent(inner: fake, baseSettings: const AppSettings());

      final res = await agent.ask(const AgentRequest('Сгенерируй на Java класс Foo'));
      expect(res.isFinal, isFalse);
      final files = (res.meta?['files'] as List?)?.cast<Map<String, String>>();
      expect(files, isNotNull);
      // Должен остаться только основной файл, без тестов
      expect(files!.length, 1);
      expect(files.first['path'], anyOf(contains('Main.java'), contains('Foo.java')));
    });

    test('start() emits code_generated with runId and without test files', () async {
      final fake = _FakeCodeOpsAgent();
      final agent = CodeOpsBuilderAgent(inner: fake, baseSettings: const AppSettings());
      final events = <AgentEvent>[];

      final stream = agent.start(const AgentRequest('Сгенерируй на Java класс Bar'))!;
      await for (final e in stream) {
        events.add(e);
      }

      // Найти событие code_generated
      final cg = events.firstWhere((e) => e.stage == AgentStage.code_generated, orElse: () => throw StateError('code_generated not found'));
      expect(cg.meta?['runId'], isNotNull);
      final files = (cg.meta?['files'] as List?)?.cast<Map<String, String>>();
      expect(files, isNotNull);
      // Проверяем, что тестовые файлы отфильтрованы
      final names = files!.map((f) => (f['path'] ?? '').toLowerCase()).toList();
      expect(names.any((n) => n.endsWith('test.java') || n.contains('/test/') || n.contains('\\test\\')), isFalse);
    });

    test('start() event sequence and meta correctness (no pipeline_complete yet)', () async {
      final fake = _FakeCodeOpsAgent();
      final agent = CodeOpsBuilderAgent(inner: fake, baseSettings: const AppSettings());

      final events = await agent.start(const AgentRequest('Генерация Java класса Baz'))!.toList();
      // Verify key stages order presence
      final stages = events.map((e) => e.stage).toList();
      expect(stages, containsAllInOrder([
        AgentStage.pipeline_start,
        AgentStage.intent_classified,
        AgentStage.code_generation_started,
        AgentStage.code_generated,
        AgentStage.ask_create_tests,
      ]));
      // Ensure pipeline_complete is NOT emitted on the first phase
      expect(stages.contains(AgentStage.pipeline_complete), isFalse);

      // pipeline_start meta
      final start = events.firstWhere((e) => e.stage == AgentStage.pipeline_start);
      expect(start.meta?['runId'], isNotNull);
      expect(start.meta?['startedAt'], isNotNull);

      // intent_classified meta
      final ic = events.firstWhere((e) => e.stage == AgentStage.intent_classified);
      expect(ic.meta?['intent'], equals('code_generate'));
      expect(ic.meta?['language'], equals('java'));

      // code_generation_started meta
      final cgs = events.firstWhere((e) => e.stage == AgentStage.code_generation_started);
      expect(cgs.meta?['language'], equals('java'));

      // code_generated meta: files without tests
      final cg = events.firstWhere((e) => e.stage == AgentStage.code_generated);
      final files = (cg.meta?['files'] as List?)?.cast<Map<String, String>>();
      expect(files, isNotNull);
      final names = files!.map((f) => (f['path'] ?? '').toLowerCase()).toList();
      expect(names.any((n) => n.endsWith('test.java') || n.contains('/test/') || n.contains('\\test\\')), isFalse);
    });

    test('start() approve path: two-phase tests (generate -> ask run -> run -> complete)', () async {
      final fake = _FakeCodeOpsAgent();
      final agent = CodeOpsBuilderAgent(inner: fake, baseSettings: const AppSettings());

      // Phase 1: code generation, ends on ask_create_tests
      await agent.start(const AgentRequest('Сгенерируй на Java класс Buzz'))!.toList();

      // Phase 2: approve tests generation (no run yet)
      final events2 = await agent.start(const AgentRequest('да'))!.toList();
      final stages2 = events2.map((e) => e.stage).toList();
      expect(stages2, containsAllInOrder([
        AgentStage.pipeline_start,
        AgentStage.test_generation_started,
        AgentStage.test_generated,
        AgentStage.ask_create_tests,
      ]));
      // Ensure no pipeline_complete yet
      expect(stages2.contains(AgentStage.pipeline_complete), isFalse);
      // test_generated meta language
      final tg = events2.firstWhere((e) => e.stage == AgentStage.test_generated);
      expect(tg.meta?['language'], equals('java'));

      // Phase 3: approve run
      final events3 = await agent.start(const AgentRequest('да'))!.toList();
      final stages3 = events3.map((e) => e.stage).toList();
      expect(stages3, containsAllInOrder([
        AgentStage.pipeline_start,
        AgentStage.docker_exec_started,
        AgentStage.docker_exec_result,
        AgentStage.pipeline_complete,
      ]));
      final complete = events3.lastWhere((e) => e.stage == AgentStage.pipeline_complete);
      expect(complete.meta?['all_green'], isTrue);
    });

    test('start() decline path: completes pipeline with skipped tests', () async {
      final fake = _FakeCodeOpsAgent();
      final agent = CodeOpsBuilderAgent(inner: fake, baseSettings: const AppSettings());

      // Phase 1: code generation, ends on ask_create_tests
      await agent.start(const AgentRequest('Сгенерируй на Java класс SkipMe'))!.toList();

      // Phase 2: decline tests
      final events2 = await agent.start(const AgentRequest('нет'))!.toList();
      final stages2 = events2.map((e) => e.stage).toList();
      expect(stages2.last, AgentStage.pipeline_complete);
      final complete = events2.lastWhere((e) => e.stage == AgentStage.pipeline_complete);
      expect(complete.meta?['tests'], equals('skipped'));
    });

    test('ask() non-stream confirms question flow and decline path', () async {
      final fake = _FakeCodeOpsAgent();
      final agent = CodeOpsBuilderAgent(inner: fake, baseSettings: const AppSettings());

      final r1 = await agent.ask(const AgentRequest('Сгенерируй на Java простой класс Qux'));
      expect(r1.isFinal, isFalse);
      expect(r1.text, contains('Создать тесты'));

      final r2 = await agent.ask(const AgentRequest('нет'));
      expect(r2.isFinal, isTrue);
      expect(r2.text.toLowerCase(), contains('тесты создавать не будем'));
    });

    test('ask() approve path generates tests and runs them with deps', () async {
      final fake = _FakeCodeOpsAgent();
      final agent = CodeOpsBuilderAgent(inner: fake, baseSettings: const AppSettings());

      // 1) Первое обращение — генерация кода и вопрос о тестах
      final r1 = await agent.ask(const AgentRequest('Сгенерируй на Java простой класс Main'));
      expect(r1.isFinal, isFalse);
      expect(r1.meta?['files'], isNotNull);

      // 2) Подтверждаем создание тестов
      final r2 = await agent.ask(const AgentRequest('да'));
      expect(r2.isFinal, isTrue);
      expect(r2.text, contains('Все тесты успешно прошли'));
      // Проверяем, что фейковый агент получил исполнение с зависимостями
      expect(fake.execCalls.length, greaterThanOrEqualTo(1));
      final call = fake.execCalls.first;
      final files = (call['files'] as List).cast<Map<String, String>>();
      final entrypoint = call['entrypoint'] as String?;
      expect(entrypoint, isNotNull);
      // Должны запускать JUnit тест по FQCN тестового класса
      expect(entrypoint!.toLowerCase(), contains('maintest'));
      // Ожидаем, что среди файлов есть сам тест и исходник Main.java
      final names = files.map((f) => (f['path'] ?? '').toLowerCase()).toList();
      expect(names.any((n) => n.endsWith('maintest.java')), isTrue);
      expect(names.any((n) => n.endsWith('main.java')), isTrue);
    });

    test('ask() remembers prompt without language and reuses it after language clarification', () async {
      final fake = _FakeCodeOpsAgent();
      final agent = CodeOpsBuilderAgent(inner: fake, baseSettings: const AppSettings());

      // 1) Пользователь просит сгенерировать код без языка
      final firstPrompt = 'Создай класс Stack с методами push/pop';
      final r1 = await agent.ask(AgentRequest(firstPrompt));
      expect(r1.isFinal, isFalse);
      expect(r1.text.toLowerCase(), contains('на каком языке'));

      // 2) Пользователь уточняет язык отдельным сообщением
      final r2 = await agent.ask(const AgentRequest('Java'));
      // Ожидаем, что это шаг генерации кода и вопрос о тестах
      expect(r2.isFinal, isFalse);
      expect(r2.meta?['files'], isNotNull);
      expect(r2.text, contains('Создать тесты'));

      // Проверяем, что во внутреннюю генерацию ушёл исходный промпт (как часть составного запроса),
      // а не слово «Java»
      expect(fake.lastCodeGenPrompt, contains(firstPrompt));
    });
  });
}

class _FakeCodeOpsAgent extends CodeOpsAgent {
  _FakeCodeOpsAgent() : super(baseSettings: const AppSettings());

  // Запишем вызовы execJavaFilesInDocker для ассертов
  final List<Map<String, dynamic>> execCalls = [];
  // Запишем последний промпт, с которым запрашивалась генерация кода (files schema)
  String? lastCodeGenPrompt;

  @override
  Future<Map<String, dynamic>> ask(
    String userText, {
    bool autoCompress = true,
    ResponseFormat? overrideResponseFormat,
    String? overrideJsonSchema,
  }) async {
    // Имитация классификации интента
    if ((overrideJsonSchema ?? '').contains('code_generate|other')) {
      final hasJava = userText.toLowerCase().contains('java');
      final lang = hasJava ? 'java' : '';
      return {
        'answer': '{"intent":"code_generate","language":"$lang","reason":"ok"}',
        'isFinal': true,
        'mcp_used': false,
      };
    }
    // Имитация ответа генерации кода, содержащего тестовый файл
    if ((overrideJsonSchema ?? '').contains('files')) {
      // запоминаем исходный промпт, пришедший на генерацию кода
      lastCodeGenPrompt = userText;
      final json = '{"title":"Foo","description":"desc","language":"java","entrypoint":"Main","files":['
          '{"path":"src/main/java/Main.java","content":"public class Main { public static void main(String[] a){} }"},'
          '{"path":"src/test/java/MainTest.java","content":"import org.junit.Test; public class MainTest { @Test public void ok(){ Main.main(new String[0]); } }"}'
        ']}';
      return {
        'answer': json,
        'isFinal': true,
        'mcp_used': false,
      };
    }
    // Имитация генерации тестов (JSON со схемой tests)
    if ((overrideJsonSchema ?? '').contains('"tests"')) {
      final testsJson = '{"tests":[{"path":"src/test/java/MainTest.java","content":"import org.junit.Test; import static org.junit.Assert.*; public class MainTest { @Test public void ok(){ Main.main(new String[0]); assertTrue(true); } }"}],"note":"ok"}';
      return {
        'answer': testsJson,
        'isFinal': true,
        'mcp_used': false,
      };
    }
    // Прочие случаи не используются в этих тестах
    return {
      'answer': '',
      'isFinal': true,
      'mcp_used': false,
    };
  }

  @override
  Future<Map<String, dynamic>> execJavaFilesInDocker({
    required List<Map<String, String>> files,
    String? entrypoint,
    String? classpath,
    List<String>? compileArgs,
    List<String>? runArgs,
    String? image,
    String? containerName,
    String? extraArgs,
    String workdir = '/work',
    int timeoutMs = 15000,
    int? cpus,
    String? memory,
    String cleanup = 'always',
  }) async {
    execCalls.add({
      'files': files,
      'entrypoint': entrypoint,
      'classpath': classpath,
      'compileArgs': compileArgs,
      'runArgs': runArgs,
      'image': image,
      'containerName': containerName,
      'extraArgs': extraArgs,
      'workdir': workdir,
      'timeoutMs': timeoutMs,
      'cpus': cpus,
      'memory': memory,
      'cleanup': cleanup,
    });
    return {
      'compile': {'exit_code': 0, 'stderr': ''},
      'run': {'exit_code': 0, 'stderr': ''},
    };
  }
}
