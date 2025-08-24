# Roadmap: Snap Trace AI

Роли: 
- App Team (Mobile), 
- Backend Team (Kotlin), 
- Integrations Team (MCP), 
- DevOps/SRE.

--------------------------------
## Веха 0: Инициация (Неделя 0)
- Репозитории: три отдельных проекта (app, server, mcp).
- Выбор фреймворков: 
  - App: Flutter/React Native (final).
  - Server: Ktor (Kotlin 2.1+).
  - MCP: Node.js/Go/Kotlin (final).
- Подготовка OpenAPI черновика — ВЫПОЛНЕНО (см. `snap_trace_ai/openapi.yaml`).

Артефакты:
- Арх диаграмма.
- OpenAPI v0 (черновик).

--------------------------------
## Веха 1: MVP сквозной поток (Недели 1–2)
- App:
  - Камера/галерея, форма промпта, отправка POST /v1/jobs.
  - Экран ленты (заглушка данных).
- Server:
  - Каркас Ktor-проекта (Kotlin 2.1+) в `snap_trace_ai/server/`.
  - Базовые эндпоинты-стабы по OpenAPI: `/health`, `POST /v1/jobs`, `GET /v1/jobs/{id}`, `GET /v1/feed`.
  - Заглушечное хранение job-статусов (in-memory), генерация UUID.
  - Готовность к замене на PostgreSQL и очереди.
  - Интеграция Yandex Art (dev конфиги), YandexGPT (dev).
  - S3 клиент (Yandex Cloud Object Storage) и сохранение медиа.
  - MCP клиент и вызов tg_send_photo.
  - GET /v1/jobs/{id}, GET /v1/feed (первые 10).
- MCP:
  - JSON‑RPC каркас, initialize/tools/list/tools/call.
  - Инструменты: tg_send_message, tg_send_photo, s3_put.
- DevOps:
  - Dev окружения, CI сборки, Docker образы.
  - Dev бакет в Yandex Object Storage.

Критерий: фото → промпт → публикация в Telegram → карточка в ленте с публичным S3 URL.

--------------------------------
## Веха 2: Надежность и наблюдаемость (Неделя 3)
- Ретраи и backoff в оркестраторе.
- Логи JSON с traceId/jobId.
- Rate limiting.
- Алёрты (ошибки MCP, S3, Yandex API).

--------------------------------
## Веха 3: UX и офлайн (Неделя 4)
- Кэш изображений и ленты.
- Оффлайн очередь отправок с ретраями.
- Улучшенные состояния (progress/failed/retry).

--------------------------------
## Веха 4: Безопасность и среды (Неделя 5)
- TLS и прокси.
- Секреты через Yandex Cloud Secrets/Lockbox.
- Разделение env: dev/stage/prod, ключи и бакеты.

--------------------------------
## Веха 5: Тестирование и качество (Неделя 6)
- Unit/интеграционные/контрактные тесты.
- Нагрузочные тесты (100 параллельных задач), целевые p95 установить по фактическим замерам.

--------------------------------
## Backlog и открытые вопросы
- Авторизация пользователей в МП (гости vs OAuth/Apple/Google).
- Модерация контента до публикации в Telegram (ручная/авто).
- Публичные ссылки S3 (Yandex Cloud Object Storage): публичный ACL vs подписанные URL vs CDN.
- Push‑уведомления о готовности результата (FCM/APNs).
- SLA/целевая производительность и стоимость (лимиты вызовов Yandex/Telegram/S3).
- Геокодирование (превращать lat/lon в placeName).
- Локализация: EN, другие языки.
- Политики хранения/удаления медиа (lifecycle rules, ретеншн) в Yandex Cloud.
- Анти‑абьюз (защита от NSFW/спама).
- UI улучшения: предпросмотр, авто‑сохранение черновика промпта.

--------------------------------
## Трекинг задач (примерные эпики)
- EPIC-APP-001: Камера+форма+отправка.
- EPIC-BE-001: Оркестрация Jobs (очередь, статусы).
- EPIC-MCP-001: JSON‑RPC каркас + инструменты.
- EPIC-DEVOPS-001: CI/CD, окружения, секреты.
- EPIC-QUALITY-001: Логи, метрики, тесты, нагрузка.

--------------------------------
## Детальный роадмап: Сервер на Kotlin (оркестратор, Ktor 3, Kotlin 2.1+)
Связь с эпиками: EPIC-BE-001, EPIC-MCP-001 (интеграции), EPIC-DEVOPS-001, EPIC-QUALITY-001

- [x] S0 — Каркас и контракты
  - [x] Проект Ktor в `snap_trace_ai/server/` (Gradle, JVM 17)
  - [x] Эндпоинты‑заглушки: `/health`, `/v1/jobs`, `/v1/jobs/{id}`, `/v1/feed`
  - [x] Билд и тесты зелёные: `.\\gradlew -p snap_trace_ai/server test`
  - [x] Синхронизация DTO с `openapi.yaml` (валидация схем)
  - [x] README сервера + диаграмма жизненного цикла job

- [ ] S1 — Приём файла (multipart) и валидация
  - [x] `POST /v1/jobs`: `multipart/form-data` (image/jpeg|png), лимит размера (config)
  - [x] Поля: `prompt`, `lat?`, `lon?`, `deviceId?`; ответ `{ jobId, status: queued }`
  - [ ] EXIF нормализация (ts, geo — опц.)
  - [x] Тесты: happy/edge; ошибки 400/415

- [ ] S2 — Очередь и статусы
  - [ ] Модель: queued → processing → published|failed
  - [ ] In-memory воркер (корутины); интерфейс на будущее (pluggable queue)
  - [ ] `GET /v1/jobs/{id}` отдаёт актуальный статус
  - [ ] Тесты: переходы статусов, ретраи с backoff (мок таймера)

- [ ] S3 — Интеграции Yandex Art/GPT
  - [ ] Клиенты с IAM: `YANDEX_IAM_TOKEN`, `YANDEX_FOLDER_ID`
  - [ ] Пайплайн: Art → изображение; GPT → подпись
  - [ ] Таймауты/ретраи, метрики длительности
  - [ ] Тесты: моки клиентов; интеграционные — за флагом

- [ ] S4 — Объектное хранилище (Yandex S3)
  - [ ] Клиент S3: `YC_S3_*`, `YC_S3_BUCKET`
  - [ ] Путь: `media/{yyyy}/{MM}/{dd}/{uuid}.jpg`
  - [ ] Политика доступа: public‑read или подписанные URL (config)
  - [ ] Тесты put/get; корректный URL

- [ ] S5 — MCP интеграция (Telegram)
  - [ ] JSON‑RPC клиент MCP; инструмент `tg_send_photo`
  - [ ] Caption = текст GPT; обработка ошибок MCP
  - [ ] Контрактные тесты по `snap_trace_ai/mcp_examples.json`

- [ ] S6 — Лента и пагинация
  - [ ] `GET /v1/feed?cursor&limit` (пока in‑memory → позже PostgreSQL)
  - [ ] Модель `FeedItem`: imageUrl, text, timestamp, location?
  - [ ] E2E: job → публикация → элемент в ленте

- [ ] S7 — PostgreSQL и миграции
  - [ ] Схема: `jobs`, `feed_items`, `media_objects` (Flyway/Liquibase)
  - [ ] Перенос логики на БД; идемпотентность по `jobId`
  - [ ] Интеграционные тесты с Testcontainers

- [ ] S8 — Надёжность и наблюдаемость
  - [ ] JSON‑логи (traceId/jobId), StatusPages, rate limiting/валидации
  - [ ] Метрики: длительности этапов, ошибки; нагрузочный тест (100 параллельных job)

- [ ] S9 — Prod‑готовность
  - [ ] Env-конфиги (dev/stage/prod), секреты (YC Lockbox/Secrets Manager)
  - [ ] Dockerfile, CI/CD пайплайн, health/readiness пробы
  - [ ] Деплой в dev/stage, smoke‑тесты

### Риски и допущения
- Ограничения Yandex API (квоты/латентность) → ретраи, очередь
- Доступ к S3: public vs signed URL — решать на DevOps этапе
- Контент‑модерация Telegram — вне MVP (фича‑флаг)

--------------------------------
## Детальный роадмап: Мобильное приложение (iOS/Android, Flutter)
Связь с эпиками: EPIC-APP-001, EPIC-QUALITY-001

- [ ] M0 — Каркас приложения и базовый UI
  - [ ] Экраны: Capture/Upload, Prompt, Feed, Settings
  - [ ] Навигация и состояние (Provider/ChangeNotifier или Riverpod)
  - [ ] Хранилище настроек: серверный URL, ключи, флаги (dev)

- [ ] M1 — Камера и загрузка медиа
  - [ ] Фото с камеры/галереи, предпросмотр, EXIF чтение (ts/geo)
  - [ ] Ввод промпта, устройства (`deviceId`), опционально geo (пермишены)
  - [ ] Отправка `multipart/form-data` на `/v1/jobs` (по `openapi.yaml`)
  - [ ] Обработка ошибок сети/валидации, повтор отправки

- [ ] M2 — Трекинг задач и фид
  - [ ] Пуллинг статуса `GET /v1/jobs/{id}` до `published|failed`
  - [ ] Экран ленты: `GET /v1/feed?cursor&limit`, карточки с текстом/фото/временем/гео
  - [ ] Пагинация/индикаторы загрузки, кэширование последних N элементов

- [ ] M3 — Настройки и безопасность
  - [ ] Переключение окружений (dev/stage/prod), проверка соединения
  - [ ] Хранение секретов/токенов безопасно (платформенные сторы), TLS проверка
  - [ ] Логи UI‑событий/ошибок для диагностики

- [ ] M4 — Качество и релиз
  - [ ] Юнит‑тесты: парсинг EXIF, формирование multipart, маппинг DTO
  - [ ] Интеграционные тесты фида (моки API)
  - [ ] Сборки Debug/Release, подпись, инструкции по публикации (README)

### Риски (mobile)
- Разрешения на камеру/гео и различия платформ — потребуют UX подсказок
- Большие изображения — ресайз/компрессия на клиенте

--------------------------------
## Детальный роадмап: MCP сервер (JSON‑RPC 2.0 интеграции)
Связь с эпиками: EPIC-MCP-001, EPIC-DEVOPS-001, EPIC-QUALITY-001

- [x] P0 — Базовый сервер и инструменты Telegram
  - [x] JSON‑RPC сервер, структурированные логи, коды ошибок
  - [x] Инструменты: `tg_send_message`, `tg_send_photo`, `tg_get_updates`
  - [x] Документация примеров: `mcp_examples.json`, README

- [ ] P1 — Инструменты для Object Storage (S3)
  - [ ] `s3_put` (контент/файл → bucket/key, ACL/public URL)
  - [ ] `s3_get` (presigned URL или прямой fetch)
  - [ ] Переменные окружения: `YC_S3_*`, `YC_S3_BUCKET`
  - [ ] Контрактные тесты (моки)

- [ ] P2 — Клиент для Kotlin‑сервера и схемы обмена
  - [ ] Стабильные payload схемы для Telegram/S3 вызовов
  - [ ] Ретраи/таймауты, backoff, идемпотентность по requestId
  - [ ] Совместимость с сервером (версии протокола, фича‑флаги)

- [ ] P3 — Безопасность и эксплуатация
  - [ ] Аутентификация (ключ/токен) и rate limiting
  - [ ] Обновлённые логи: traceId/jobId корреляция с сервером
  - [ ] Dockerfile/Compose и health‑check

### Риски (MCP)
- Ограничения Telegram API (скорость, модерация) — очереди/делей
- Настройка S3 прав доступа — чёткие политики bucket/объектов
