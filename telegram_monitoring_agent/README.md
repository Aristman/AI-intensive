# Telegram Monitoring Agent / Агент Мониторинга Telegram

## Описание проекта

Telegram Monitoring Agent - это интеллектуальный агент для мониторинга, анализа и автоматизации коммуникаций в Telegram. Агент использует LLM (Large Language Models) для суммаризации сообщений, анализа тональности и генерации автоматических ответов. Поддерживает интеграцию с MCP (Model Context Protocol) серверами для расширенной функциональности.

## Основные возможности

### 📊 Мониторинг и анализ сообщений
- **Непрерывный мониторинг** чатов и каналов Telegram
- **Фильтрация сообщений** по ключевым словам, длине, отправителям
- **Парсинг сообщений** с извлечением текста, отправителя, даты
- **Анализ тональности и намерений** с помощью LLM
- **Извлечение ключевых сущностей** (люди, организации, темы, даты)

### 🤖 Интеграция с LLM
- **Суммаризация сообщений** на русском языке
- **Генерация автоматических ответов** на основе анализа
- **Анализ тональности** (положительная, отрицательная, нейтральная)
- **Определение намерений** (вопрос, утверждение, команда и т.д.)
- **Извлечение сущностей** и тем из текста

### 🔗 Интеграция с MCP
- **MCP сервер для Telegram (STDIO)** — взаимодействие по STDIO без сети
- **Локальный сервер**: `mcp_servers/telegram_mcp_server/src/index.js` (Node.js 18+)
- **Учётные данные Telegram** читаются ТОЛЬКО на стороне сервера из `.env`
- **Отправка сообщений**, уведомлений и пересылка
- **Разрешение чатов** и получение истории
- **Асинхронная обработка** для высокой производительности

### 🔒 Безопасность и надежность
- **Фильтрация чувствительных данных** в логах
- **Механизмы переподключения** при потере связи
- **Health-checks** для мониторинга состояния
- **Логирование всех действий** с уровнем детализации
- **Таймауты и обработка ошибок** для стабильности

### 🎨 Пользовательский интерфейс
- **Графический интерфейс** на Tkinter
- **Отображение сообщений** в чате (пользователь/агент)
- **Кнопки управления** (очистка контекста, настройки)
- **Статус подключений** и уведомления

## Архитектура проекта

### Структура файлов
```
telegram_monitoring_agent/
├── src/
│   ├── __init__.py
│   ├── agent.py          # Основной класс агента
│   ├── mcp_client.py     # Клиент для MCP сервера
│   └── ui.py             # Графический интерфейс
├── tests/
│   └── test_agent.py     # Тесты
├── config/
│   └── config.json       # Конфигурация
├── docs/
│   └── setup.md          # Инструкция по настройке
├── logs/
│   └── telegram_agent.log # Логи
├── requirements.txt      # Зависимости
├── README.md            # Документация
├── main.py              # Точка входа
└── roadmap.md           # План разработки
```

### Ключевые компоненты

#### TelegramAgent
Основной класс агента, который:
- Управляет конфигурацией и инициализацией
- Координирует мониторинг чатов
- Обрабатывает сообщения с фильтрацией и анализом
- Генерирует автоматические ответы
- Обеспечивает логирование и health-checks

#### MCPClient
Клиент для взаимодействия с MCP сервером:
- Транспорт: STDIO. Локально запускает Node.js сервер `mcp_servers/telegram_mcp_server/src/index.js` и общается по JSON-RPC 2.0 через stdin/stdout.
- Безопасность: клиент НЕ передает Telegram‑креды в процесс и не хранит их. Сервер загружает их из `.env` на своей стороне.
- Методы:
  - `resolve_chat()` — разрешение идентификаторов чатов
  - `fetch_history()` — получение истории сообщений
  - `send_message()` — отправка сообщений
  - `forward_message()` — пересылка сообщений

#### LLM Integration
Интеграция с OpenAI API для:
- Суммаризации текста
- Анализа тональности и намерений
- Генерации ответов
- Извлечения сущностей

## Зависимости

- **Python 3.8+**
- **aiohttp>=3.8.0** — HTTP-клиент (опционально, для HTTP LLM API)
- **tkinter>=8.6** — GUI интерфейс
- **Node.js 18+** — для MCP сервера Telegram (см. `mcp_servers/telegram_mcp_server`)
- NPM зависимости MCP сервера устанавливаются отдельно в `mcp_servers/telegram_mcp_server`

## Быстрый старт

1. **Установите зависимости Python**
   ```bash
   pip install -r requirements.txt
   ```

2. **Установите зависимости MCP сервера (Node.js)**
   ```bash
   # один раз
   npm ci --prefix mcp_servers/telegram_mcp_server
   ```

3. **Настройте учётные данные Telegram на стороне MCP сервера**
   Создайте файл `.env` в `mcp_servers/telegram_mcp_server/` и заполните переменные:
   ```env
   TELEGRAM_API_ID=...
   TELEGRAM_API_HASH=...
   TELEGRAM_PHONE_NUMBER=+1234567890
   # Либо используйте бот‑токен (используйте только один из вариантов авторизации)
   TELEGRAM_BOT_TOKEN=...
   ```
   Допустимы два режима аутентификации (выберите один):
   - User (MTProto): `TELEGRAM_API_ID`, `TELEGRAM_API_HASH`, `TELEGRAM_PHONE_NUMBER`
   - Bot API: `TELEGRAM_BOT_TOKEN`

4. **Настройте конфигурацию агента**
   Отредактируйте `config/config.json` под ваши чаты и LLM‑настройки. Транспорт MCP должен быть `"stdio"`. Telegram‑креды сюда НЕ добавляются.

5. **Запустите агента**
   ```bash
   python main.py
  ```

## Деплой на удалённый сервер (вместе с MCP сервером)

Подробная инструкция: см. `telegram_monitoring_agent/docs/deploy_remote.md`.

Кратко:
- Развернуть репозиторий на удалённом хосте.
- Создать venv и установить зависимости:
  - `pip install -r telegram_monitoring_agent/requirements.txt`
  - `pip install -r mcp_servers/telegram_mcp_server_py/requirements.txt`
- Настроить `mcp_servers/telegram_mcp_server_py/.env` (рекомендуется бот‑токен) и выполнить `python -m mcp_servers.telegram_mcp_server_py.cli_login` для создания `session.txt`.
- Проверить связь: `python telegram_monitoring_agent/main.py --list-tools`.

Запуск в фоне:
- Linux/macOS (nohup):
  ```bash
  nohup python -u telegram_monitoring_agent/main.py > logs/agent.out 2>&1 &
  echo $! > logs/agent.pid
  # Остановка:
  kill $(cat logs/agent.pid)
  ```
- Linux (systemd) — пример `ai-agent.service` и `ai-mcp.service` см. в `docs/deploy_remote.md`.
- Windows (PowerShell):
  ```powershell
  $logDir = "logs"; if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
  Start-Process -FilePath "python" -ArgumentList "-u", "telegram_monitoring_agent/main.py" -WindowStyle Hidden -RedirectStandardOutput "logs/agent.out" -RedirectStandardError "logs/agent.err"
  ```

## API ключи и настройки

### Ключи агента (client‑side)
- **LLM провайдер и ключи** — например, `deepseek_api_key`, `yandex_iam_token` и т.п.
- **Настройки анализа и UI** — `filters`, `ui_theme`, `log_level` и т.д.
- MCP транспорт фиксирован: `mcp_transport: "stdio"` (URL не используется)

### Учётные данные Telegram (server‑side, `.env`)
Хранятся ТОЛЬКО в `mcp_servers/telegram_mcp_server/.env` и загружаются сервером через `dotenv`.
- User (MTProto): `TELEGRAM_API_ID`, `TELEGRAM_API_HASH`, `TELEGRAM_PHONE_NUMBER`
- Bot API: `TELEGRAM_BOT_TOKEN`
Используйте один режим за раз.

### Пример `config/config.json`
```json
{
  "use_userbot": true,
  "mcp_transport": "stdio",
  "chats": ["@SourceCraft", "@prog_tools", "@my_aigents"],
  "ui_theme": "light",
  "log_level": "DEBUG",
  "llm_provider": "deepseek",
  "deepseek_api_key": "",
  "deepseek_temperature": 0.2,
  "deepseek_max_tokens": 2000,
  "yandex_iam_token": "",
  "yandex_api_key": "",
  "yandex_folder_id": "b1golisqrg02h9b6u39de",
  "yandex_temperature": 0.2,
  "yandex_max_tokens": 2000,
  "monitor_interval_sec": 86400,
  "page_size": 10,
  "chunk_size": 12,
  "summary_chat": "@aigents_report",
  "filters": {
    "keywords": ["ai", "ml", "deep learning", "neural networks", "ИИ"],
    "exclude_senders": [],
    "min_length": 10
  }
}
```

## Использование

### Мониторинг чатов
Агент автоматически мониторит настроенные чаты и:
- Фильтрует сообщения по критериям
- Анализирует тональность и намерения
- Извлекает ключевые сущности
- Генерирует автоматические ответы

### Генерация ответов
Для сообщений с вопросами или командами агент:
- Анализирует контекст
- Определяет тональность
- Генерирует подходящий ответ на русском
- Отправляет ответ в чат

### Логирование и мониторинг
- Все действия логируются в файл `logs/telegram_agent.log`
- Health-checks выполняются автоматически
- При потере соединения происходит переподключение

## Разработка и тестирование

### Запуск тестов
```bash
python -m unittest tests/test_agent.py -v
```

### Добавление новых функций
1. Добавьте методы в соответствующие классы
2. Напишите тесты для новых методов
3. Обновите документацию
4. Проверьте совместимость с существующими функциями

### Отладка
- Логи сохраняются в `logs/telegram_agent.log`
- Уровень логирования настраивается в config.json
- Health-checks показывают статус всех компонентов

## Безопасность

- **Telegram‑креды не хранятся в клиентском конфиге** — только в `mcp_servers/telegram_mcp_server/.env`
- **Чувствительные данные** фильтруются в логах
- **Таймауты** предотвращают зависания
- **Обработка ошибок** обеспечивает стабильность работы

## Ограничения и будущие улучшения

### Текущие ограничения
- Требуется настройка MCP сервера
- Ограниченная поддержка Telegram API (через MCP)
- Зависимость от OpenAI API

### Планы развития
- Поддержка других LLM провайдеров
- Расширенная аналитика сообщений
- Интеграция с внешними системами
- Улучшенный пользовательский интерфейс

## Контрибьюция

1. Форкните репозиторий
2. Создайте ветку для вашей функции
3. Добавьте тесты для новых функций
4. Убедитесь, что все тесты проходят
5. Создайте Pull Request

## Лицензия

MIT License - свободное использование с сохранением авторских прав.

## Контакты

Для вопросов и предложений создавайте issues в репозитории проекта.
