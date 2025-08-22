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
  streaming: false,
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
