# CodeOpsBuilderAgent

Оркестратор поверх `CodeOpsAgent`, реализующий унифицированный интерфейс `IAgent`/`IToolingAgent` и добавляющий управляемый поток разработки кода и тестов для Java.

## Расположение
- Файл: `sample_app/lib/agents/code_ops_builder_agent.dart`
- Тесты: `sample_app/test/code_ops_builder_agent_test.dart`

## Возможности
- Генерация кода по пользовательскому запросу (многофайловые ответы через JSON-схему).
- Уточнение: спрашивает пользователя, создавать ли тесты.
- Автогенерация JUnit4‑тестов для Java (через LLM).
- Запуск тестов в Docker через MCP (`docker_exec_java`), разбор результатов.
- Итеративное улучшение тестов (одна попытка доработки на каждый упавший тест).
- Не изменяет существующий `CodeOpsAgent`, использует композицию.

## Ограничения
- Автозапуск тестов поддержан только для Java (JUnit 4: `org.junit.Test`, `static org.junit.Assert.*`).
- Требуется включённый MCP‑сервер и корректный `mcpServerUrl` в настройках приложения.

## Интерфейс
Класс реализует:
- `IAgent` — методы `capabilities`, `ask(AgentRequest)`, `start(AgentRequest?)`, `updateSettings(AppSettings)`, `dispose()`.
- `IToolingAgent` — прокидывает `docker_exec_java` и `docker_start_java` во внутренний `CodeOpsAgent`.

### Capabilities
```dart
AgentCapabilities(
  stateful: true,
  streaming: true,
  reasoning: true,
  tools: {'docker_exec_java', 'docker_start_java'},
)
```

## Поток работы
1) Пользователь формулирует задачу: «Сгенерируй класс …».
2) Агент классифицирует интент как `code_generate`, генерирует JSON с файлами кода. Тестовые файлы на этом шаге намеренно исключаются из результата оркестратором (фильтрация происходит на стадии публикации события `code_generated`).
3) Агент задаёт вопрос: «Создать тесты и прогнать их?»
4) Если пользователь подтверждает и язык — Java:
   - Генерируются JUnit4‑тесты.
   - Для каждого теста подбираются зависимости (исходный класс), строится корректный `entrypoint` (FQCN теста), и выполняется `docker_exec_java`.
   - Анализируется результат; при падениях выполняется одна попытка автоматической доработки теста и повторный запуск.
5) Возвращается отчёт (compile/run exit codes, stderr/short), флаг использования MCP.

Важное изменение жизненного цикла пайплайна:
- Стадия `pipeline_complete` эмитится ТОЛЬКО после завершения тестовой фазы (включая возможный рефайн) либо после явного отказа пользователя создавать тесты. После генерации кода пайплайн не завершается – он переходит в ожидание подтверждения создания тестов.

## События и стриминг
Агент поддерживает поток событий через `IAgent.start(...)` (см. интерфейс `AgentEvent`, `AgentStage`, `AgentSeverity` в `sample_app/lib/agents/agent_interface.dart`).

Ключевые стадии пайплайна:
- `pipeline_start`, `intent_classified`
- `code_generation_started`, `code_generated`
- `ask_create_tests`
- `test_generation_started`, `test_generated`
- `docker_exec_started`, `docker_exec_progress`, `docker_exec_result`
- `analysis_started`, `analysis_result`
- `refine_tests_started`, `refine_tests_result`
- `pipeline_complete`, `pipeline_error`

Примечания к последовательности:
- После `code_generated` следует первое `ask_create_tests` c `meta.action = "create_tests"`. На этом месте стрим первой фазы завершается без `pipeline_complete`.
- При подтверждении (через повторный `start()` с ответом «да») агент эмитит `test_generation_started` и один или несколько `test_generated`.
- Затем следует второе `ask_create_tests` с `meta.action = "run_tests"` — запрос на запуск уже сгенерированных тестов.
- При повторном подтверждении («да») запускаются тесты (`docker_exec_*`) и после анализа эмитится `pipeline_complete`.
- При отказе на любом из этапов («нет») агент немедленно завершает пайплайн событием `pipeline_complete` с пометкой, что тесты пропущены.

Структура события:
```
AgentEvent(
  id, runId, stage, severity=info, message,
  progress? (0..1), stepIndex?, totalSteps?, timestamp, meta?
)
```

## Контекст и корреляция (runId)
- Контекст диалога и данные пайплайна (userText, intent, language, entrypoint, files, статус, время начала/завершения) сохраняются на уровне оркестратора `CodeOpsBuilderAgent`.
- Каждый запуск пайплайна имеет уникальный `runId`. Он добавляется в каждое событие `AgentEvent` и в `meta` ключевых событий (например, `code_generated`). Это позволяет UI корректно коррелировать события с конкретным запуском.
- Краткая история сообщений поддерживается в самом оркестраторе (не во внутреннем `CodeOpsAgent`). Внутренний агент отвечает только за генерацию кода/тестов.

### Мульти‑ходовое поведение и продолжение
- Если пользователь просит сгенерировать код без указания языка, оркестратор сохранит исходный промпт и попросит уточнить язык.
- При последующем коротком ответе‑уточнении (например, «Java») метод `start()` обрабатывает продолжение: используется сохранённый промпт + указанный язык, запускается генерация кода и далее стандартный поток с вопросом о тестах.

### Интеграция в UI
- Экран `CodeOpsScreen` (`sample_app/lib/screens/code_ops_screen.dart`) подписывается на `Stream<AgentEvent>`:
  - показывает прогресс пайплайна (`LinearProgressIndicator`) и live‑лог событий,
  - визуализирует сгенерированные файлы как карточки кода (с кнопками запуска/теста для Java),
  - обрабатывает стадию `ask_create_tests` (кнопки подтверждения), различая `meta.action = create_tests` и `meta.action = run_tests`,
  - отправляет подтверждения обратно агенту через повторный потоковый вызов `start()` (мульти‑ходовая континуация),
  - отображает `test_generated` как карточки тестов с кнопкой запуска; события содержат `meta.language` и список `meta.tests`.
  

Рекомендации по meta:
- `code_generated`: `{ files: [{path, content, isTest:false}], language? }`
- `ask_create_tests`: `{ action: 'create_tests' | 'run_tests', language? }`
- `test_generated`: `{ language: 'java', tests: [{ path, content }] }`
- `docker_exec_started`: `{ testName, entrypoint, classpath }`
- `docker_exec_progress`: `{ current, total, testName? }`
- `docker_exec_result`: `{ testName, exitCode, durationMs, stdoutTail, stderrTail }`
- `analysis_result`: `{ total, passed, failed: [testName], notes }`
- `refine_tests_result`: `{ refinedFiles: [{path, content}], notes }`
- `pipeline_error`: `{ errorCode, details }`

## Использование
Пример (псевдокод):
```dart
final agent = CodeOpsBuilderAgent(baseSettings: settings);
final r1 = await agent.ask(AgentRequest('Сгенерируй класс калькулятора на Java'));
// Агент вернёт сводку с файлами и вопрос про тесты
final r2 = await agent.ask(AgentRequest('да'));
// r2 содержит отчёт о запуске тестов
```

## Тесты
- Юнит‑тесты проверяют базовые возможности: `capabilities`, доступность инструментов, guard при отключённом MCP.
- Дополнительно покрыто поведение оркестратора:
  - фильтрация тестовых файлов из результата генерации кода (`code_generated` не содержит тестов),
  - наличие `runId` в событиях стриминга,
  - DI: возможность инжектировать фейковый `CodeOpsAgent` через конструктор для тестов.
- Запуск: `cd sample_app && flutter test`.

## Примечания по реализации
- Генерация/рефайн тестов выполняется через `_inner.ask(..., ResponseFormat.json)` с малой схемой.
- Для подбора зависимостей и точки входа используются утилиты из `sample_app/lib/utils/code_utils.dart` (`collectTestDeps`, `fqcnFromFile`).
- Маркер финала ответа наследуется от `CodeOpsAgent.stopSequence` и удаляется из текста для пользователя.
