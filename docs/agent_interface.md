# Агентный интерфейс и функциональность

Этот документ описывает унифицированный интерфейс агента, общие классы, события и возможности (capabilities). Он разработан для постепенной миграции существующих агентов без их немедленного изменения.

- Базовая реализация интерфейса: `sample_app/lib/agents/agent_interface.dart`
- Существующие агенты (на момент документа):
  - `sample_app/lib/agents/agent.dart` — базовый stateful агент со стримом
  - `sample_app/lib/agents/simple_agent.dart` — stateless консультант
  - `sample_app/lib/agents/reasoning_agent.dart` — рассуждающий агент
  - `sample_app/lib/agents/code_ops_agent.dart` — инженерный агент (CodeOps)

## Цели
- __Унификация контрактов__ ответов и запросов, включая финальность, MCP-использование и неопределённость.
- __Расширяемость__: декларирование возможностей (streaming, reasoning, tools).
- __Совместимость__: не требует немедленных изменений в старых агентах.

## Интерфейсы и общие типы
Файл: `sample_app/lib/agents/agent_interface.dart`

- __AgentRequest__
  - `input: String`
  - `timeout?: Duration`
  - `context?: Map<String, dynamic>` — внешний контекст
  - `overrideFormat?: ResponseFormat`
  - `overrideJsonSchema?: String`

- __AgentResponse__
  - `text: String`
  - `isFinal: bool`
  - `mcpUsed: bool`
  - `uncertainty?: double (0..1)`
  - `meta?: Map<String, dynamic>` — телеметрия, токены, traceId и пр.

- __AgentCapabilities__
  - `stateful: bool`
  - `streaming: bool`
  - `reasoning: bool`
  - `tools: Set<String>` — имена инструментов (e.g. `docker_exec_java`)

- __AgentEvent__
  - `type: 'token' | 'response' | 'tool_call' | 'error' | 'debug'`
  - `data: dynamic`

- __IAgent__
  - `AgentCapabilities get capabilities`
  - `Future<AgentResponse> ask(AgentRequest req)`
  - `Stream<AgentEvent>? start(AgentRequest req)` — опционально
  - `void updateSettings(AppSettings settings)`
  - `void dispose()`

- __IStatefulAgent__ (mixin)
  - `void clearHistory()`
  - `int get historyDepth`

- __IToolingAgent__
  - `bool supportsTool(String name)`
  - `Future<Map<String, dynamic>> callTool(String name, Map<String, dynamic> args, {Duration? timeout})`

- __AgentTextUtils__
  - `extractUncertainty(String)` — извлекает значение 0..1 (RU/EN, проценты)
  - `stripStopToken(String, stopToken)` — удаляет stop-токен, возвращает пару `(text, hadStop)`

## Схема агента
```
+-----------------+           +------------------------+
|   IAgent        |           |  Dependencies          |
|-----------------|           |------------------------|
| ask(req)        |---------> |  LlmUseCase.complete   |
| start(req)      |----.      |  McpIntegrationService |
| updateSettings  |    |      |  (enrich + prompt)     |
| dispose         |    |      +------------------------+
| capabilities    |    |
+-----------------+    |
                       |
      (optional) events v
                 +------------------+
                 |  AgentEvent      |
                 | 'token','error', |
                 | 'tool_call', ... |
                 +------------------+

Stateful agents implement IStatefulAgent (clearHistory, historyDepth)
Tool-enabled agents implement IToolingAgent (supportsTool, callTool)
```

## Маппинг существующих агентов
- __agent.dart__
  - Stateful, streaming=true (через собственный Stream), reasoning зависит от настроек.
  - Может быть адаптирован к `IAgent.start()` без изменения текущего API.

- __simple_agent.dart__
  - Stateless, streaming=false, reasoning=false, tools={}.
  - `ask()` → можно маппить к `IAgent.ask()` с `AgentResponse(isFinal=true)`.

- __reasoning_agent.dart__
  - Stateful, streaming=false, reasoning=true.
  - Вычисляет финальность по stop-токену и анализирует неопределённость (можно передавать в `AgentResponse.uncertainty`).

- __code_ops_agent.dart__
  - Stateful, streaming=false, reasoning=true, tools={`docker_exec_java`, `docker_start_java`}.
  - Инструменты можно экспонировать через `IToolingAgent` без изменения текущей логики.

## Рекомендации по интеграции
- Новые агенты создавайте сразу как `IAgent`/`IStatefulAgent`/`IToolingAgent`.
- Постепенная адаптация существующих агентов возможна через thin-adapters.
- Для вывода в UI используйте:
  - `ask()` для простых сценариев.
  - `start()` для прогрессивного стриминга.

## Примеры использования
```dart
final req = AgentRequest(
  'Проанализируй репозиторий',
  timeout: const Duration(seconds: 30),
  overrideFormat: ResponseFormat.text,
);

final agent = /* некая реализация IAgent */;
final res = await agent.ask(req);
if (res.isFinal) {
  print('Ответ: ${res.text}');
}
```

## Тестирование
- Тесты для общих классов и утилит: `sample_app/test/agent_interface_test.dart`.
- Существующие агентные тесты остаются без изменений.

## Совместимость и миграция
- Текущие агенты продолжают работать без изменений.
- Адаптация к интерфейсу выполняется постепенно, с добавлением thin-adapters и покрывающих тестов.
