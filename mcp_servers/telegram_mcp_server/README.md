# Telegram STDIO MCP Server

MCP-сервер для работы с Telegram API через STDIO транспорт. Реализует инструменты для взаимодействия с Telegram через MTProto и Bot API.

## Описание

Сервер предоставляет следующие инструменты (только префикс `tg.*`):
- `tg.resolve_chat` — разрешение информации о чате
- `tg.fetch_history` — история сообщений с пагинацией
- `tg.read_messages` — чтение сообщений (эквивалент fetch_history)
- `tg.send_message` — отправка сообщения
- `tg.forward_message` — пересылка сообщения
- `tg.mark_read` — пометка сообщений как прочитанных
- `tg.get_unread_count` — количество непрочитанных сообщений
- `tg.get_chats` — список доступных чатов

## Требования

- Node.js 18.0 или выше
- Аккаунт Telegram с полученными API ключами или бот-токен

## Установка

1. Перейдите в директорию сервера:
   ```bash
   cd mcp_servers/telegram_mcp_server
   ```

2. Установите зависимости:
   ```bash
   npm install
   ```

## Конфигурация

### Настройка учётных данных

**ВАЖНО: Учётные данные хранятся на сервере и не передаются от клиента!**

1. Создайте файл `.env` в корне `mcp_servers/telegram_mcp_server/`:
   ```env
   # mcp_servers/telegram_mcp_server/.env
   TELEGRAM_API_ID=ваш_api_id
   TELEGRAM_API_HASH=ваш_api_hash
   TELEGRAM_PHONE_NUMBER=+1234567890
   # Вариант для бота (используйте либо блок выше, либо этот)
   TELEGRAM_BOT_TOKEN=ваш_bot_token
   ```

2. Откройте `.env` и настройте переменные окружения:

#### Для пользовательской аутентификации (MTProto):
```env
TELEGRAM_API_ID=ваш_api_id
TELEGRAM_API_HASH=ваш_api_hash
TELEGRAM_PHONE_NUMBER=+1234567890
```

#### Для бот-аутентификации:
```env
TELEGRAM_BOT_TOKEN=ваш_bot_token
```

### Получение API ключей Telegram

Для пользовательской аутентификации:
1. Перейдите на [https://my.telegram.org](https://my.telegram.org)
2. Авторизуйтесь
3. Создайте новое приложение (API Development tools)
4. Скопируйте `api_id` и `api_hash`

Для бот-аутентификации:
1. Напишите [@BotFather](https://t.me/botfather) в Telegram
2. Создайте нового бота командой `/newbot`
3. Скопируйте полученный токен

## Запуск сервера

```bash
npm start
```

При первом запуске с пользовательской аутентификацией сервер запросит код подтверждения от Telegram. Следуйте инструкциям в консоли.

## Архитектура

- **Транспорт**: STDIO (стандартный ввод/вывод)
- **Протокол**: JSON-RPC 2.0 через MCP
- **Библиотека**: [@modelcontextprotocol/sdk](https://github.com/modelcontextprotocol/sdk)
- **Telegram клиент**: [telegram](https://github.com/gram-js/gramjs) для MTProto, встроенный Bot API для ботов

## Интеграция с клиентом

Сервер автоматически запускается клиентом `telegram_monitoring_agent` при старте. Клиент использует STDIO транспорт для коммуникации с сервером по MCP протоколу.

### Примеры инструментов и аргументов

Ниже приведены примеры для инструментов `tg.*` и нормализации ключей аргументов.

#### Разрешение чата (resolve)
Ключи: `chatId` (основной), также принимаются `chat` или `input` в алиасе.
```json
{
  "name": "tg.resolve_chat",
  "arguments": {
    "chat": "@username"
  }
}
```

Ответ:
```json
{
  "id": 1234567890,
  "username": "username",
  "title": "Chat Title",
  "type": "Channel|Chat|User"
}
```

#### История сообщений (history)
Ключи: `chat`, `page_size`, `min_id`, `max_id`. Поддерживается также `offset`.
```json
{
  "name": "tg.fetch_history",
  "arguments": {
    "chat": "@username",
    "page_size": 50,
    "min_id": 0,
    "max_id": null
  }
}
```

Ответ:
```json
{
  "messages": [
    {
      "id": 111,
      "text": "...",
      "date": "2024-09-01T12:34:56.000Z",
      "from": { "id": 222, "display": "Sender Name" }
    }
  ]
}
```

Также доступно: `tg.read_messages` — с теми же аргументами, что и выше.

#### Отправка сообщения (send)
Ключи: `chat`, `message` (поддерживается также `text`).
```json
{
  "name": "tg.send_message",
  "arguments": {
    "chat": "@username",
    "message": "Привет!"
  }
}
```

Ответ:
```json
{ "message_id": 12345 }
```

#### Пересылка сообщения (forward)
Ключи: `from_chat`, `message_id`, `to_chat` (поддерживаются также `fromChatId`, `messageId`, `toChatId`).
```json
{
  "name": "tg.forward_message",
  "arguments": {
    "from_chat": "@source_chat",
    "message_id": 12345,
    "to_chat": "@target_chat"
  }
}
```

Ответ:
```json
{ "forwarded_id": 67890 }
```

#### Маркировка как прочитанное (read)
```json
{
  "name": "tg.mark_read",
  "arguments": {
    "chat": "@username",
    "message_ids": [12345, 12346]
  }
}
```

Ответ:
```json
{ "success": true }
```

#### Количество непрочитанных (unread)
Поддерживает опциональный аргумент `chat` для запроса по конкретному чату.
```json
{
  "name": "tg.get_unread_count",
  "arguments": {
    "chat": "@username"
  }
}
```

Ответ:
```json
{ "unread": 42 }
```

#### Список чатов (chats)
```json
{
  "name": "tg.get_chats",
  "arguments": {}
}
```

Ответ:
```json
[
  { "id": 1, "title": "Chat A", "username": "chat_a", "unread": 0 },
  { "id": 2, "title": "Chat B", "username": null, "unread": 5 }
]
```

## Работа с сервером со стороны клиента (MCP протокол)

Сервер использует STDIO транспорт для общения с клиентами через JSON-RPC 2.0 протокол. Клиент должен запустить процесс сервера и обмениваться сообщениями через stdin/stdout.

### Подключение к серверу

1. Запустите сервер как subprocess в вашем приложении
2. Установите переменные окружения перед запуском
3. Обменивайтесь JSON-RPC сообщениями

#### Пример на Node.js:
```javascript
const { spawn } = require('child_process');

const server = spawn('node', ['src/index.js'], {
  cwd: '/path/to/mcp_servers/telegram_mcp_server',
  env: {
    ...process.env,
    TELEGRAM_API_ID: 'your_api_id',
    TELEGRAM_API_HASH: 'your_api_hash',
    TELEGRAM_PHONE_NUMBER: 'your_phone'
  }
});

// Чтение ответов
server.stdout.on('data', (data) => {
  const response = JSON.parse(data.toString());
  console.log('Response:', response);
});

// Отправка запроса
const request = {
  jsonrpc: '2.0',
  id: 1,
  method: 'initialize',
  params: {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: {
      name: 'your-client',
      version: '1.0.0'
    }
  }
};

server.stdin.write(JSON.stringify(request) + '\n');
```

### Протокол JSON-RPC

Все сообщения следуют формату JSON-RPC 2.0.

#### Инициализация
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": {
      "name": "telegram-client",
      "version": "1.0.0"
    }
  }
}
```

#### Получение списка инструментов
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list",
  "params": {}
}
```

#### Вызов инструмента
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "tg.send_message",
    "arguments": {
      "chat": "@username",
      "message": "Привет из MCP!"
    }
  }
}
```

#### Пример ответа на вызов инструмента
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": { "message_id": 12345 }
}
```

#### Обработка ошибок
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "error": {
    "code": -32603,
    "message": "Internal error",
    "data": {
      "details": "Failed to send message: Chat not found"
    }
  }
}
```

### Рекомендации по интеграции

1. **Асинхронность**: Все операции с сервером асинхронны. Используйте promises или async/await.
2. **Обработка ошибок**: Всегда проверяйте наличие поля `error` в ответах.
3. **Идентификаторы запросов**: Используйте уникальные `id` для каждого запроса.
4. **Graceful shutdown**: Корректно завершайте процесс сервера при выходе из приложения.
5. **Логирование**: Включайте логирование для отладки, особенно при первой настройке 2FA.

### Ресурсы MCP

На данный момент ресурсы не реализованы и возвращают пустой список. В будущем планируется добавление ресурсов для доступа к чатам и сообщениям.

## Ограничения и TODO

- **2FA обработка**: Пока что требует ручного ввода кода. В будущем планируется автоматизация.
- **Пагинация**: В `get_chat_history` пагинация реализована базово. Требуется доработка для полной поддержки.
- **Ресурсы**: Пока что ресурсы MCP не реализованы (заглушки).
- **Безопасность**: Храните API ключи в безопасном месте.

## Архитектура

```
src/
├── config.js      # Конфигурация и переменные окружения
├── utils.js       # Вспомогательные функции (клиент Telegram, утилиты)
├── handlers/
│   ├── resources.js # Обработчики ресурсов MCP
│   └── tools.js     # Обработчики инструментов MCP
└── index.js        # Точка входа и инициализация сервера
```

## Разработка

Для разработки установите зависимости и запускайте сервер:
```bash
npm install
npm start
```

## Лицензия

MIT License

## Поддержка

При возникновении проблем проверьте:
1. Правильность API ключей
2. Наличие всех переменных окружения
3. Версию Node.js (минимум 18.0)
4. Доступность Telegram API

Для отладки добавьте логирование в код или используйте `--verbose` флаг, если поддерживается.
