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
- MCP: внешний сервер, URL вида `ws://localhost:8080` (задаётся в Настройках)
- Локальная конфигурация: используйте `assets/.env.example` и скопируйте его в `assets/.env`, затем заполните значения. `.env` игнорируется Git.
  - Переменные:
    - `IAM_TOKEN`
    - `X_FOLDER_ID`
    - `YANDEX_API_KEY`
    - `MCP_URL` (например, `ws://localhost:8080`)

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
- Персист (SharedPreferences), MCP клиент и YandexGPT — в работе (см. `ROADMAP.md`).

## CI
- Настроен GitHub Actions для анализа и тестов Flutter: `.github/workflows/flutter-ci.yml`.

## План MVP (функциональность)
- Чат-UI: AppBar (название, текущая модель; кнопки Очистка/Настройки), лента сообщений, поле ввода и Отправить
- Рендер `structuredContent` в карточках со сводной информацией (кнопка «Копировать»)
- Персист контекста/настроек через SharedPreferences

## Тесты
```bash
flutter test
```

## Структура (основное)
- `lib/ui/chat_screen.dart` — основной экран чата
- `lib/ui/settings_screen.dart` — экран настроек (план)
- `lib/state/` — состояние (настройки, чат)
- `lib/data/llm/` — клиент YandexGPT (заготовка)
- `lib/data/mcp/` — клиент MCP WebSocket JSON-RPC (заготовка)
- `lib/widgets/` — визуальные компоненты (MessageBubble, SummaryCard)

Подробный план — см. `ROADMAP.md`.
