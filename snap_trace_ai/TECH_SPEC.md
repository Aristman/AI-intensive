# ТЗ: Snap Trace AI

Цель: Реализовать систему из трех независимых компонентов:
1) Мобильное приложение (iOS/Android): делает фото, принимает промпт, отправляет на сервер; отображает ленту “фото + текст + время + геометка”.
2) Сервер на Kotlin: оркестрация — принимает фото+промпт, вызывает Yandex Art и YandexGPT, публикует через MCP (Telegram, хранилище), сохраняет результат и отдает ленту.
3) MCP‑сервер: JSON‑RPC шлюз к внешним сервисам (Telegram, Yandex Cloud Object Storage S3).

Принятое решение: итоговое файловое хранилище — Yandex Cloud Object Storage (совместимое с S3 API).

--------------------------------
## 1. Мобильное приложение

### 1.1. Платформы и стек
- Платформы: iOS 14+ и Android 8+.
- Технологии: Flutter/React Native/Native — допускается любой выбор при условии:
  - Доступ к камере/галерее.
  - Отправка multipart/form-data.
  - Локальный кэш изображений.
  - Пагинация ленты.

### 1.2. Пользовательские сценарии
- Сделать фото/выбрать из галереи.
- Ввести промпт (текст).
- Отправить задачу обработки на сервер.
- Отслеживать статус (queued/processing/published/failed).
- Просматривать ленту карточек (последние N).
- Детальный просмотр карточки, шаринг.
- Опционально: включать/выключать геометку.

### 1.3. API (между МП и сервером)
- POST /v1/jobs
  - multipart/form-data: file=image, fields: prompt:string, lat:float?, lon:float?, deviceId?:string
  - resp: { jobId:string, status:"queued" }
- GET /v1/jobs/{jobId}
  - resp: { status:"queued|processing|published|failed", error?:string, result?:FeedItem }
- GET /v1/feed?cursor&limit
  - resp: { items: FeedItem[], nextCursor?:string }
- Модель FeedItem:
  - { id:string, imageUrl:string, text:string, timestamp:string(ISO-8601), location?:{lat:float, lon:float, placeName?:string} }

Аутентификация:
- MVP: без аккаунтов (guest), ограничение rate‑limit по deviceId/IP.
- Транспорт: HTTPS only.

### 1.4. Нефункциональные требования
- Производительность: загрузка ленты 10 элементов <1.5 c (4G).
- Надежность: авто‑ретраи отправок в оффлайне; кэширование изображений.
- Безопасность: TLS, проверка MIME, лимит размера файла (например, ≤ 15 МБ).

### 1.5. Тестирование
- Unit: модели/парсинг/форматирование дат.
- UI: рендер карточек, пустые/ошибочные состояния.
- E2E: отправка фото → появление карточки (на стейдже/с моками).

--------------------------------
## 2. Сервер на Kotlin (оркестратор)

### 2.1. Технологии
- Язык: Kotlin 2.1+.
- Фреймворк: Ktor.
- Асинхронность: coroutines.
- БД: PostgreSQL (таблицы jobs, feed_items, media_objects).
- Хранилище: Yandex Cloud Object Storage (S3 совместимый).
- Интеграции:
  - Yandex Art API (IAM) — img2img/редактирование по промпту.
  - YandexGPT API (IAM) — описание/суммаризация.
  - MCP‑клиент по JSON‑RPC (WebSocket/HTTP) — инструменты Telegram, S3‑операции.

### 2.2. Публичные API (см. раздел 1.3)
- POST /v1/jobs, GET /v1/jobs/{id}, GET /v1/feed, GET /health.

OpenAPI:
- Поддерживать спецификацию OpenAPI 3.0+ (yaml/json в репозитории).
- Контрактные тесты на основе спецификации.

### 2.3. Поток обработки (внутри)
1) Принять задачу: валидация файла, MIME, лимиты размера.
2) Сохранить во временное хранилище (tmp) либо сразу загрузить в S3 (префикс tmp/).
3) Воркфлоу:
   - Yandex Art: применить промпт к изображению; получить итоговое изображение (bytes/URL).
   - YandexGPT: сгенерировать текст‑описание/суммаризацию (учитывать промпт).
   - Публикация:
     - Сохранить финальное изображение в S3: bucket=<env>, key=media/{yyyy}/{MM}/{dd}/{uuid}.jpg.
     - Через MCP.tg_send_photo опубликовать в Telegram (caption = текст).
4) Создать FeedItem: imageUrl=публичный S3 URL (или CDN), text=из шага GPT, timestamp=serverNow, location=из запроса (если было).
5) Обновить job: status=published; resultItemId=feed_item.id.

Очередь/воркеры:
- Таблица jobs с состояниями: queued → processing → published|failed.
- Ретраи с backoff при сетевых ошибках.
- Идемпотентность по jobId.

### 2.4. Хранилище (Yandex Cloud Object Storage)
- Доступ по S3 API.
- Публичные ссылки через статический хостинг/подписанные URLs или CDN (выбор на этапе DevOps).
- ENV:
  - YC_S3_ENDPOINT, YC_S3_BUCKET, YC_S3_ACCESS_KEY, YC_S3_SECRET_KEY, YC_S3_REGION
- Политики: доступ “read public” по key-префиксу media/ или доступ по подписанным ссылкам (решение на этапе внедрения).

### 2.5. Секреты и конфигурация
- YANDEX_IAM_TOKEN, YANDEX_FOLDER_ID (для Art/GPT).
- MCP_URL, MCP_API_KEY (клиентский ключ).
- TELEGRAM_CHAT_ID (передавать в MCP инструмент или хранить на стороне MCP).
- DB_URL, DB_USER, DB_PASSWORD.
- SERVER_BASE_URL, MAX_UPLOAD_MB, ALLOWED_MIME=image/jpeg|png.
- Все секреты — из секрет‑хранилища (например, YC Lockbox/Secrets Manager) и env.

### 2.6. Безопасность и соответствие
- TLS (за обратным прокси).
- Валидация параметров, rate limiting, защита от DoS.
- Логи JSON с traceId/jobId, без утечек персональных данных.

### 2.7. Тестирование и качество
- Unit: клиенты Yandex Art/GPT (моки), парсеры, сервисы S3.
- Интеграционные: е2е job → публикация → feed_item.
- Контрактные: соответствие OpenAPI.
- Нагрузочные: 100 параллельных задач, p95 времени обработки — зафиксировать после пилота.

### 2.8. CI/CD
- Docker‑образ; миграции БД (Flyway/Liquibase).
- Environments: dev, stage, prod.
- Каталоги/переменные окружения для каждого env.

--------------------------------
## 3. MCP‑сервер интеграций

### 3.1. Протокол
- JSON‑RPC 2.0.
- Транспорт: WebSocket (приоритет) или HTTP(S).
- Методы:
  - initialize → { serverVersion, tools }
  - tools/list → [{ name, paramsSchema }]
  - tools/call(name, params) → result|error

### 3.2. Инструменты (минимум)
- tg_send_message
  - params: { chat_id:string, text:string, parse_mode?:string }
  - result: { message_id:int, date:int }
- tg_send_photo
  - params: { chat_id:string, photo:(url|base64), caption?:string, parse_mode?:string }
  - result: { message_id:int, date:int, photo:[{file_id,width,height}] }
- s3_put (Yandex Cloud Object Storage)
  - params: { bucket?:string, key:string, content_base64:string, content_type:string, acl?:string }
  - result: { url:string, etag?:string }
- s3_get (опц.)
  - params: { bucket?:string, key:string }
  - result: { content_base64:string, content_type:string }

### 3.3. Безопасность MCP
- Аутентификация клиента: MCP_API_KEY (handshake при initialize).
- Секреты сервисов (TELEGRAM_BOT_TOKEN, YC_S3_*): только в окружении MCP.
- Rate limiting, аудит, структурные логи (traceId, durationMs).
- Идемпотентность: clientRequestId (если передан).

### 3.4. Тесты
- Unit: валидация параметров.
- Интеграционные: Telegram (за флагом) и S3 (dev‑бакет).
- Контракты: примеры JSON‑RPC вызовов.

### 3.5. Деплой
- Отдельный контейнер.
- ENV:
  - MCP_API_KEY
  - TELEGRAM_BOT_TOKEN
  - TELEGRAM_DEFAULT_CHAT_ID
  - YC_S3_ENDPOINT, YC_S3_BUCKET, YC_S3_ACCESS_KEY, YC_S3_SECRET_KEY, YC_S3_REGION
- Health: /healthz (HTTP) или ping (WS).

--------------------------------
## 4. Критерии приемки (сквозной сценарий)
1) МП отправляет POST /v1/jobs с фото+промптом (+гео).
2) Сервер обрабатывает: Yandex Art → YandexGPT → s3_put → tg_send_photo через MCP.
3) Сервер сохраняет FeedItem (публичный S3 URL, текст, timestamp, гео).
4) МП в ленте видит карточку с изображением и текстом.
5) Логи и статусы задач прозрачны (queued/processing/published/failed).
