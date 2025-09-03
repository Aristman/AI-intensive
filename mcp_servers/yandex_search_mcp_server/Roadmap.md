# Yandex Search MCP Server — Roadmap

Дата: 2025-09-03

## Цели
- Реализовать STDIO MCP сервер на ESM JS для работы с Yandex Search API (sync web search).
- Аутентификация: API Key по аналогии с YandexGPT (Authorization: Api-Key <key> + x-folder-id).
- Минимально совместимые методы MCP: initialize, tools/list, tools/call (и пустые resources/list|read).

## Архитектура
- src/index.js — точка входа, STDIO цикл, JSON-RPC роутинг.
- src/handlers/tools.js — инструменты MCP (list/call), yandex_search_web.
- src/handlers/resources.js — ресурсы MCP (заглушка list/read).
- src/config.js — конфигурация (env, ключи, базовые URL).
- src/utils.js — утилиты: фрейминг Content-Length, JSON-RPC ответы/ошибки, валидация.
- package.json — ESM, скрипты.

## План (чекбокс-лист)
- [x] Базовый каркас STDIO: разбор Content-Length, чтение/запись фреймов.
- [x] JSON-RPC базовые методы: initialize, tools/list, tools/call.
- [x] Инструмент yandex_search_web:
  - [x] Вход: { query (string, req), page (int>=1), pageSize (1..50), region (string) }.
  - [x] Выход: content = [ text, json(results) ].
  - [x] HTTP: fetch к Yandex Search v2; headers: Authorization: Api-Key, x-folder-id.
  - [x] Обработка ошибок/таймаут, логирование в stderr.
  - [x] Ретраи 5xx (экспоненциальная пауза). 
  - [ ] Нормализация/ограничение ответов (TODO).
- [x] resources/list|read — пустые заглушки.
- [x] Конфигурация через ENV: YANDEX_API_KEY, YANDEX_FOLDER_ID, YANDEX_SEARCH_BASE_URL, REQUEST_TIMEOUT_MS.
- [x] Документация: краткое описание протокола в комментариях и TODO для пагинации.
- [ ] Тестирование локально: ручная проверка через stdin/stdout.
- [ ] Улучшения: кэширование, продвинутые параметры региона, источники, i18n.

## Переменные окружения
- YANDEX_API_KEY — обязательный.
- YANDEX_FOLDER_ID — обязательный (по аналогии с YandexGPT, передаем в x-folder-id).
- YANDEX_SEARCH_BASE_URL — опционально (default: https://api.search.yandexcloud.net/v2/web/search).
- REQUEST_TIMEOUT_MS — опционально (default: 15000).

## Замечания
- Весь лог и ошибки — через stderr (console.error). Stdout — только JSON-RPC фреймы.
- Все сетевые вызовы — async/await. Заглушки помечены TODO.
