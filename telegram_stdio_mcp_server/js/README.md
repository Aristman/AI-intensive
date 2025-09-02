# Telegram MCP Server (JavaScript версия)

MCP-сервер для работы с Telegram API на основе Model Context Protocol. Реализует асинхронные инструменты для взаимодействия с Telegram через MTProto протокол.

## Описание

Сервер предоставляет следующие возможности через MCP инструменты:
- Разрешение информации о чатах
- Чтение истории сообщений с пагинацией
- Отправка текстовых сообщений
- Пересылка сообщений между чатами
- Маркировка сообщений как прочитанных
- Получение количества непрочитанных сообщений

## Требования

- Node.js 18.0 или выше
- Аккаунт Telegram с полученными API ключами

## Установка

1. Клонируйте репозиторий или перейдите в папку проекта:
   ```bash
   cd telegram_stdio_mcp_server/js
   ```

2. Установите зависимости:
   ```bash
   npm install
   ```

## Конфигурация

### Получение API ключей Telegram

1. Перейдите на [https://my.telegram.org](https://my.telegram.org)
2. Авторизуйтесь
3. Создайте новое приложение (API Development tools)
4. Скопируйте `api_id` и `api_hash`

### Переменные окружения

Создайте файл `.env` в корне проекта или установите переменные окружения:

```bash
export TELEGRAM_API_ID="ваш_api_id"
export TELEGRAM_API_HASH="ваш_api_hash"
export TELEGRAM_PHONE_NUMBER="+1234567890"
```

### Пример .env файла
```env
TELEGRAM_API_ID=12345678
TELEGRAM_API_HASH=abcdef1234567890abcdef
TELEGRAM_PHONE_NUMBER=+1234567890
```

## Запуск сервера

```bash
npm start
```

При первом запуске сервер запросит код подтверждения от Telegram (2FA). Следуйте инструкциям в консоли.

## Использование

Сервер работает через STDIO и предназначен для интеграции с MCP-совместимыми приложениями.

### Примеры инструментов

#### Разрешение чата
```json
{
  "name": "resolve_chat",
  "arguments": {
    "chatId": "@username"
  }
}
```

#### Получение истории чата
```json
{
  "name": "get_chat_history",
  "arguments": {
    "chatId": "@username",
    "limit": 50,
    "offset": 0
  }
}
```

#### Отправка сообщения
```json
{
  "name": "send_message",
  "arguments": {
    "chatId": "@username",
    "text": "Привет!"
  }
}
```

#### Пересылка сообщения
```json
{
  "name": "forward_message",
  "arguments": {
    "fromChatId": "@source_chat",
    "messageId": 12345,
    "toChatId": "@target_chat"
  }
}
```

#### Маркировка как прочитанное
```json
{
  "name": "mark_read",
  "arguments": {
    "chatId": "@username",
    "messageIds": [12345, 12346]
  }
}
```

#### Количество непрочитанных
```json
{
  "name": "get_unread_count",
  "arguments": {}
}
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
  cwd: '/path/to/telegram_stdio_mcp_server/js',
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
    "name": "send_message",
    "arguments": {
      "chatId": "@username",
      "text": "Привет из MCP!"
    }
  }
}
```

#### Пример ответа на вызов инструмента
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"messageId\": 12345}"
      }
    ]
  }
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
