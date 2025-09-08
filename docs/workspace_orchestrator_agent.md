# Workspace Orchestrator Agent ("Кодер")

MVP-реализация агента правой панели экрана `WorkspaceScreen`.

## Роль и задачи
- Общение с пользователем в правой панели (чистое LLM на этапе MVP).
- Хранение и восстановление контекста беседы (SharedPreferences).
- Отображение сообщений и автопрокрутка в конец ленты.
- Управление историей диалога (очистка истории).

Дальнейшие этапы (после MVP):
- Определение намерений (intents) и построение плана работ.
- Делегирование атомарных действий другим агентам (через MCP/локальные вызовы).
- Публикация промежуточных и финальных результатов в чат.

## Архитектура
- Интерфейс: `sample_app/lib/agents/agent_interface.dart` (`IAgent`, `IStatefulAgent`, `AgentRequest`, `AgentResponse`, `AgentCapabilities`).
- Реализация агента: `sample_app/lib/agents/workspace_orchestrator_agent.dart`.
  - Использует `resolveLlmUseCase(AppSettings)` для выбора провайдера LLM.
  - Поддерживает сохранение истории через `ConversationStorageService`.
  - `conversationKey`: `workspace_orchestrator`.
  - На этапе MVP — без инструментов и стриминга.

## Интеграция в UI
- Экран: `sample_app/lib/screens/workspace_screen.dart`.
  - Правая панель (заголовок «Кодер»): чат с агентом.
  - Ширина панели увеличена до 600 px.
  - Поле ввода «Сообщение» — многострочное, Enter = перенос строки, высота авто‑расширяется (minLines=1, maxLines=6).
  - Кнопка отправки — иконка (без надписи).
  - Автопрокрутка в конец ленты при открытии экрана и при получении новых сообщений.
  - Кнопка очистки истории (иконка корзины в заголовке).

## Ключевые методы
- `WorkspaceOrchestratorAgent.ask(AgentRequest)` → `AgentResponse` — единичный запрос/ответ LLM.
- `WorkspaceOrchestratorAgent.setConversationKey(String)` — загрузка истории из `SharedPreferences`.
- `WorkspaceOrchestratorAgent.clearHistoryAndPersist()` — очистка истории и персиста.

## Настройки
- `AppSettings` (`sample_app/lib/models/app_settings.dart`):
  - применяется общая конфигурация LLM (выбор провайдера, параметры генерации).
  - `historyDepth` ограничивает количество хранимых сообщений.

## Маршрутизация
- Экран зарегистрирован в `sample_app/lib/screens/screens.dart` как `Screen.workspace`.

## Тестирование
- Базовые тесты для этого экрана/агента планируются на финальном этапе разработки (см. `roadmaps/ROADMAP_workspace_orchestrator_agent.md`).
