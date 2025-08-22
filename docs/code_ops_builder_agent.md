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
2) Агент классифицирует интент как `code_generate`, генерирует JSON с файлами кода.
3) Агент задаёт вопрос: «Создать тесты и прогнать их?»
4) Если пользователь подтверждает и язык — Java:
   - Генерируются JUnit4‑тесты.
   - Для каждого теста подбираются зависимости (исходный класс), строится корректный `entrypoint` (FQCN теста), и выполняется `docker_exec_java`.
   - Анализируется результат; при падениях выполняется одна попытка автоматической доработки теста и повторный запуск.
5) Возвращается отчёт (compile/run exit codes, stderr/short), флаг использования MCP.

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

Структура события:
```
AgentEvent(
  id, runId, stage, severity=info, message,
  progress? (0..1), stepIndex?, totalSteps?, timestamp, meta?
)
```

### Интеграция в UI
- Экран `CodeOpsScreen` (`sample_app/lib/screens/code_ops_screen.dart`) подписывается на `Stream<AgentEvent>`:
  - показывает прогресс пайплайна (`LinearProgressIndicator`) и live‑лог событий,
  - визуализирует сгенерированные файлы как карточки кода (с кнопками запуска/теста для Java),
  - обрабатывает стадию `ask_create_tests` (кнопки подтверждения).
  

Рекомендации по meta:
- `code_generated`: `{ files: [{path, content, isTest:false}] }`
- `test_generated`: `{ files: [{path, content, isTest:true}] }`
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
- Запуск: `cd sample_app && flutter test`.

## Примечания по реализации
- Генерация/рефайн тестов выполняется через `_inner.ask(..., ResponseFormat.json)` с малой схемой.
- Для подбора зависимостей и точки входа используются утилиты из `sample_app/lib/utils/code_utils.dart` (`collectTestDeps`, `fqcnFromFile`).
- Маркер финала ответа наследуется от `CodeOpsAgent.stopSequence` и удаляется из текста для пользователя.
