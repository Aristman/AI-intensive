# Telegram Summarizer

Flutter приложение-агент для суммаризации с LLM (YandexGPT) и подключаемым MCP (WebSocket JSON-RPC).

- Android packageId: `ru.marslab.telegram_summarizer`
- iOS bundle identifier: `ru.marslab.telegram.summarizer`
- Отображаемое имя: Telegram Summarizer

## Быстрый старт

1) Установите Flutter (версия, совместимая с репо; проверено на 3.22+)
2) Установите зависимости:
   ```bash
   flutter pub get
   ```
3) Запуск (пример для Windows):
   ```bash
   flutter run -d windows
   ```
   или Web:
   ```bash
   flutter run -d chrome
   ```

## Настройки
- LLM: YandexGPT через IAM + `x-folder-id` (указываются в экране Настроек, сохраняются в SharedPreferences)
- MCP: внешний сервер, URL может быть в виде `ws://`/`wss://` или `http://`/`https://` (в приложении `http(s)` автоматически конвертируется в `ws(s)` при подключении). Пример: `https://tgtoolkit.azazazaza.work`.
- Локальная конфигурация: используйте `assets/.env.example` и скопируйте его в `assets/.env`, затем заполните значения. `.env` игнорируется Git.
  - Переменные:
    - `IAM_TOKEN`
    - `X_FOLDER_ID`
    - `YANDEX_API_KEY`
    - `MCP_URL` (например, `https://tgtoolkit.azazazaza.work` или `ws://localhost:8080`)

## Платформенные заметки
- iOS: подпись и сборка
  1) Откройте `ios/Runner.xcworkspace` в Xcode.
  2) В Signing & Capabilities выберите вашу команду (Team).
  3) Убедитесь, что Bundle Identifier = `ru.marslab.telegram.summarizer` (для `Runner`) и `ru.marslab.telegram.summarizer.RunnerTests` (для тестов).
  4) При необходимости выполните установку pod'ов:
     ```bash
     cd ios && pod install
     ```

## Состояние на 2025-08-28
- Обновлён iOS bundle id во всех конфигурациях проекта Xcode.
- `CFBundleDisplayName` = "Telegram Summarizer" подтверждён.
- Исправлены виджет‑тесты (устранён pending Timer при скролле).
- Интеграция MCP централизована в `SimpleAgent` (агент): `capabilities` подгружается после соединения и добавляется в системную подсказку LLM, `askRich()` возвращает `structuredContent` при успешном ответе MCP. `ChatState` не вызывает MCP напрямую.
- В AppBar добавлен индикатор статуса MCP и кнопка «Переподключить»:
  - жёлтый — идёт подключение (минимум 250 мс, чтобы избежать мигания),
  - зелёный — подключено,
  - красный — отключено/ошибка (ошибка отображается во всплывающем уведомлении).
  - При запуске выполняется автоподключение MCP и обновление `capabilities` в агенте.

- Тултип индикатора MCP при подключении теперь показывает краткий список доступных инструментов (capabilities/tools) — например: `Инструменты: tg.resolve, tg.fetch`.

- SummaryCard: отображает строковое поле `summary` отдельным блоком над JSON. Добавлены виджет‑тесты рендера и копирования, а также виджет‑тесты индикатора статуса MCP и кнопки переподключения. Все тесты проходят (`flutter test`).

- E2E‑тесты для MCP capabilities:
  - `test/chat_screen_e2e_capabilities_test.dart` — проверяет, что capabilities добавляются в системное сообщение LLM и появляется `SummaryCard`.
  - `test/chat_screen_e2e_caps_influence_test.dart` — демонстрирует влияние capabilities: ответ LLM отличается при наличии/отсутствии capabilities; тултип показывает список инструментов при подключении.

## CI
- Настроен GitHub Actions для анализа и тестов Flutter: `.github/workflows/flutter-ci.yml`.

## План MVP (функциональность)
- Чат-UI: AppBar (название, текущая модель; кнопки Очистка/Настройки), лента сообщений, поле ввода и Отправить
- Индикация MCP: статус соединения (жёлтый/зелёный/красный), кнопка «Переподключить», проверка при старте
- Рендер `structuredContent` в карточках со сводной информацией (кнопка «Копировать»)
- Персист контекста/настроек через SharedPreferences

## SimpleAgent (контекст + сжатие + MCP)
Простой агент с сохранением истории сообщений, возможностью её сжатия, и централизованной интеграцией MCP.

- Особенности:
  - Сохраняет историю сообщений в оперативной памяти в формате `[{role, content}]`.
  - Опциональный системный промпт при создании.
  - Метод `ask()` добавляет сообщение пользователя, вызывает LLM и добавляет ответ ассистента.
  - Метод `askRich()` делает всё как `ask()`, а также при наличии подключённого MCP вызывает `summarize` и возвращает `structuredContent` вместе с текстом LLM.
  - Метод `refreshMcpCapabilities()` вызывает `capabilities` на MCP и добавляет результат в системную подсказку LLM (как дополнительное системное сообщение) для контекстно‑осознанных ответов.
  - Метод `compressContext()` сжимает историю в одну системную сводку и (опционально) оставляет последнее сообщение пользователя.

- Использование:
  ```dart
  import 'package:telegram_summarizer/agents/simple_agent.dart';
  import 'package:telegram_summarizer/data/mcp/mcp_client.dart';
  import 'package:telegram_summarizer/state/settings_state.dart';
  import 'package:telegram_summarizer/domain/llm_resolver.dart';

  final settings = SettingsState();
  await settings.load();
  final llm = resolveLlmUseCase(settings);
  final mcp = McpClient(url: settings.mcpUrl);
  await mcp.connect();

  final agent = SimpleAgent(
    llm,
    systemPrompt: 'Вы — полезный ассистент.',
    mcp: mcp,
  );
  await agent.refreshMcpCapabilities(); // подтянуть capabilities и добавить в системную подсказку

  final rich = await agent.askRich('Привет!', settings);
  final text = rich.text; // ответ LLM
  final structured = rich.structuredContent; // JSON сводка от MCP (если подключено и без ошибок)

  // Опционально: сжать контекст
  await agent.compressContext(settings, keepLastUser: true);
  ```

## Тесты
```bash
flutter test
```

## Структура (основное)
- `lib/ui/chat_screen.dart` — основной экран чата
- `lib/ui/settings_screen.dart` — экран настроек (план)
- `lib/state/` — состояние (настройки, чат). `ChatState` делегирует всю логику LLM+MCP агенту и не вызывает MCP напрямую.
- `lib/data/llm/` — клиент YandexGPT
- `lib/data/mcp/` — клиент MCP WebSocket JSON-RPC (`connect/disconnect`, `call`, `summarize`)
- `lib/agents/` — `SimpleAgent` (контекст, сжатие, интеграция MCP: `askRich`, `refreshMcpCapabilities`)
- `lib/widgets/` — визуальные компоненты (MessageBubble, SummaryCard)

Подробный план — см. `ROADMAP.md`.
