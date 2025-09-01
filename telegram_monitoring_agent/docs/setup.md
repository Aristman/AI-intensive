# Инструкция по настройке Telegram Monitoring Agent

## Предварительные требования

### Системные требования
- **Операционная система**: Windows, Linux или macOS
- **Python**: версия 3.8 или выше
- **Доступ к интернету** для API запросов

### Необходимые аккаунты и API ключи
1. **OpenAI API Key** - для работы с LLM функциями
2. **Telegram API** (опционально):
   - API ID и API Hash для Userbot
   - ИЛИ Bot Token для Telegram Bot
3. **MCP сервер** - для доступа к Telegram API

---

## Шаг 1: Установка Python и зависимостей

### 1.1 Установка Python
Если Python не установлен, скачайте и установите с [официального сайта](https://python.org):
```bash
# Проверьте версию Python
python --version
# Или
python3 --version
```

### 1.2 Установка зависимостей
```bash
# Перейдите в директорию проекта
cd telegram_monitoring_agent

# Установите зависимости
pip install -r requirements.txt
```

---

## Шаг 2: Настройка API ключей

### 2.1 Настройка DeepSeek API Key
1. Перейдите на [DeepSeek Platform](https://platform.deepseek.com)
2. Зарегистрируйтесь или войдите в аккаунт
3. Перейдите в раздел "API Keys"
4. Создайте новый API ключ
5. Скопируйте ключ для использования в конфигурации

### 2.2 Настройка YandexGPT API
#### Вариант A: IAM токен (рекомендуется)
1. Перейдите в [Yandex Cloud Console](https://console.cloud.yandex.ru)
2. Создайте сервисный аккаунт или используйте существующий
3. Сгенерируйте IAM токен для аккаунта
4. Создайте или выберите каталог (folder) для работы
5. Скопируйте **IAM токен** и **ID каталога**

#### Вариант B: API ключ
1. Перейдите в раздел "API Keys" в Yandex Cloud Console
2. Создайте новый API ключ
3. Скопируйте **API ключ** и **ID каталога**

### 2.3 Настройка Telegram API (опционально)

#### Вариант A: Userbot (рекомендуется)
1. Перейдите на [Telegram API](https://my.telegram.org)
2. Войдите с вашим номером телефона
3. Перейдите в "API development tools"
4. Создайте новое приложение
5. Скопируйте **API ID** и **API Hash**

#### Вариант B: Telegram Bot
1. Напишите [@BotFather](https://t.me/botfather) в Telegram
2. Используйте команду `/newbot`
3. Следуйте инструкциям для создания бота
4. Скопируйте **Bot Token**

### 2.3 Настройка MCP сервера
Для работы с Telegram через MCP вам понадобится:
- MCP сервер с поддержкой Telegram API
- URL сервера (обычно `http://localhost:3000`)

---

## Шаг 3: Конфигурация приложения

### 3.1 Основные настройки
Отредактируйте файл `config/config.json`:

```json
{
  "telegram_api_id": "12345678",
  "telegram_api_hash": "your_telegram_api_hash",
  "telegram_bot_token": "your_bot_token_if_using_bot",
  "use_userbot": true,
  "mcp_server_url": "http://localhost:3000",
  "chats": ["@telegram"],
  "llm_provider": "deepseek",
  "deepseek_api_key": "your_deepseek_api_key_here",
  "deepseek_temperature": 0.7,
  "deepseek_max_tokens": 2000,
  "yandex_iam_token": "your_yandex_iam_token_here",
  "yandex_api_key": "your_yandex_api_key_here",
  "yandex_folder_id": "your_yandex_folder_id_here",
  "yandex_temperature": 0.7,
  "yandex_max_tokens": 2000,
  "filters": {
    "keywords": ["important", "urgent"],
    "exclude_senders": [],
    "min_length": 10
  },
  "log_level": "INFO"
}
```

### 3.2 Подробное описание параметров конфигурации

#### Основные параметры
- **`telegram_api_id`** (string): ID вашего Telegram приложения
  - Получается на https://my.telegram.org
  - Обязательно для Userbot режима
  - Пример: "<TELEGRAM_API_ID>"

- **`telegram_api_hash`** (string): Hash вашего Telegram приложения
  - Получается на https://my.telegram.org
  - Обязательно для Userbot режима
  - Пример: "<TELEGRAM_API_HASH>"

- **`telegram_bot_token`** (string): Токен Telegram бота
  - Получается от @BotFather
  - Обязательно для Bot режима
  - Пример: "<TELEGRAM_BOT_TOKEN>"

- **`use_userbot`** (boolean): Режим работы с Telegram
  - `true`: использовать Userbot (рекомендуется)
  - `false`: использовать Bot
  - По умолчанию: `true`

- **`mcp_server_url`** (string): URL MCP сервера
  - Адрес сервера для Telegram API
  - По умолчанию: `"http://localhost:3000"`
  - Пример: `"http://localhost:3000"`

- **`chats`** (array): Список чатов для мониторинга
  - Массив строк с именами чатов
  - Поддерживает @username и прямые ссылки
  - Пример: `["@telegram", "@news"]`

#### Параметры интерфейса
- **`ui_theme`** (string): Тема пользовательского интерфейса
  - Возможные значения: `"light"`, `"dark"`
  - По умолчанию: `"light"`

- **`log_level`** (string): Уровень детализации логов
  - Возможные значения: `"DEBUG"`, `"INFO"`, `"WARNING"`, `"ERROR"`
  - По умолчанию: `"INFO"`

#### Параметры LLM провайдера
- **`llm_provider`** (string): Выбор LLM провайдера
  - Возможные значения: `"deepseek"`, `"yandexgpt"`
  - По умолчанию: `"deepseek"`

#### Параметры DeepSeek
- **`deepseek_api_key`** (string): API ключ DeepSeek
  - Получается на https://platform.deepseek.com
  - Обязательно при выборе DeepSeek
  - Пример: "<DEEPSEEK_API_KEY>"

- **`deepseek_temperature`** (number): Креативность ответов DeepSeek
  - Диапазон: 0.0 - 2.0
  - Низкие значения: более детерминированные ответы
  - Высокие значения: более креативные ответы
  - По умолчанию: `0.7`

- **`deepseek_max_tokens`** (number): Максимальное количество токенов
  - Максимальная длина ответа
  - Диапазон: 1 - 4096
  - По умолчанию: `2000`

#### Параметры YandexGPT
- **`yandex_iam_token`** (string): IAM токен Yandex Cloud
  - Получается в Yandex Cloud Console
  - Рекомендуется для production

- **`yandex_api_key`** (string): API ключ Yandex Cloud
  - Альтернатива IAM токену

- **`yandex_folder_id`** (string): ID каталога Yandex Cloud
  - ID каталога для работы с API
  - Обязательно для YandexGPT

- **`yandex_temperature`** (number): Креативность ответов YandexGPT
  - Диапазон: 0.0 - 1.0
  - Низкие значения: более детерминированные ответы
  - Высокие значения: более креативные ответы
  - По умолчанию: `0.7`

- **`yandex_max_tokens`** (number): Максимальное количество токенов
  - Максимальная длина ответа
  - Диапазон: 1 - 8000
  - По умолчанию: `2000`

#### Параметры фильтрации сообщений
- **`filters`** (object): Настройки фильтрации сообщений
  - **`keywords`** (array): Ключевые слова для фильтрации
    - Массив строк
    - Сообщения должны содержать хотя бы одно ключевое слово
    - Пример: `["важное", "срочное"]`

  - **`exclude_senders`** (array): Исключаемые отправители
    - Массив строк с именами пользователей
    - Эти отправители будут игнорироваться
    - Пример: `["spam_bot", "advertisement"]`

  - **`min_length`** (number): Минимальная длина сообщения
    - Сообщения короче этого значения будут игнорироваться
    - По умолчанию: `10`
    - Пример: `5`

---

## Шаг 4: Настройка MCP сервера

### 4.1 Установка MCP сервера
Если у вас еще нет MCP сервера:

```bash
# Клонируйте репозиторий MCP сервера
git clone https://github.com/chaindead/telegram-mcp.git
cd telegram-mcp

# Установите зависимости
npm install

# Настройте конфигурацию
cp config.example.json config.json
# Отредактируйте config.json с вашими Telegram API ключами
```

### 4.3 Настройка удаленного MCP сервера (VPS)

Если MCP сервер запущен на VPS, у вас есть два варианта подключения:

#### Вариант A: SSH Tunneling (рекомендуется для STDIO)
```json
{
  "mcp_transport": "stdio",
  "mcp_server_command": "telegram-mcp",
  "mcp_ssh_tunnel": {
    "enabled": true,
    "host": "your-vps-ip",
    "port": 22,
    "user": "your-ssh-user",
    "key_path": "~/.ssh/id_rsa",
    "remote_command": "telegram-mcp"
  }
}
```

**Настройка на VPS:**
```bash
# 1. Установите telegram-mcp на VPS
ssh user@vps-ip
git clone https://github.com/chaindead/telegram-mcp.git
cd telegram-mcp
npm install

# 2. Настройте аутентификацию на VPS
telegram-mcp auth --app-id YOUR_API_ID --api-hash YOUR_API_HASH --phone YOUR_PHONE

# 3. MCP сервер готов к удаленному подключению
```

#### Вариант B: HTTP транспорт
```json
{
  "mcp_transport": "http",
  "mcp_http_remote": {
    "enabled": true,
    "url": "http://your-vps-ip:3000"
  }
}
```

**Настройка на VPS:**
```bash
# 1. Установите telegram-mcp с HTTP сервером
ssh user@vps-ip
git clone https://github.com/chaindead/telegram-mcp.git
cd telegram-mcp
npm install

# 2. Настройте HTTP сервер в config.json
# Добавьте HTTP endpoint в конфигурацию

# 3. Запустите с HTTP поддержкой
npm start -- --port 3000 --host 0.0.0.0
```

#### Безопасность SSH подключения:
- Используйте SSH ключи вместо паролей
- Настройте firewall на VPS (разрешите только SSH и HTTP)
- Регулярно обновляйте SSH ключи
- Мониторьте логи подключений

#### Тестирование удаленного подключения:
```bash
# Для SSH tunneling
python -c "import asyncio; from src.agent import TelegramAgent; agent = TelegramAgent(); asyncio.run(agent.test_connection())"

# Для HTTP транспорта
curl http://your-vps-ip:3000/health
```

---

## Шаг 5: Тестирование установки

### 5.1 Проверка конфигурации
```bash
# Запустите агента в тестовом режиме
python main.py --test

# Или проверьте конфигурацию вручную
python -c "from src.agent import TelegramAgent; agent = TelegramAgent(); print('Конфигурация загружена успешно')"
```

### 5.2 Запуск тестов
```bash
# Запустите unit-тесты
python -m unittest tests/test_agent.py -v
```

### 5.3 Проверка подключений
```bash
# Проверьте health-check
python -c "import asyncio; from src.agent import TelegramAgent; agent = TelegramAgent(); asyncio.run(agent.health_check())"
```

---

## Шаг 6: Запуск агента

### 6.1 Основной запуск
```bash
# Запустите агента
python main.py
```

### 6.2 Режимы работы
- **GUI режим**: Запускается графический интерфейс
- **Консоль режим**: Все логи выводятся в консоль
- **Фоновый режим**: Агент работает в фоне (требует дополнительных настроек)

### 6.3 Мониторинг работы
- Логи сохраняются в `logs/telegram_agent.log`
- Используйте health-checks для проверки состояния
- Мониторьте использование API в OpenAI dashboard

---

## Шаг 7: Устранение неполадок

### 7.1 Проблемы с OpenAI API
```
Ошибка: LLM API key not configured
Решение: Проверьте llm_api_key в config.json
```

```
Ошибка: LLM summarization error
Решение: Проверьте баланс на OpenAI аккаунте
```

### 7.2 Проблемы с Telegram API
```
Ошибка: Could not resolve chat
Решение: Проверьте корректность chat ID в конфигурации
```

```
Ошибка: Telegram connection failed
Решение: Проверьте API ID/Hash или Bot Token
```

### 7.3 Проблемы с MCP сервером
```
Ошибка: MCP connection failed
Решение: Проверьте, что MCP сервер запущен и доступен
```

### 7.4 Общие проблемы
```
Ошибка: Module not found
Решение: Установите зависимости: pip install -r requirements.txt
```

```
Ошибка: Permission denied
Решение: Проверьте права доступа к файлам конфигурации
```

---

## Шаг 8: Продвинутые настройки

### 8.1 Кастомизация фильтров
```json
"filters": {
  "keywords": ["важное", "urgent", "help"],
  "exclude_senders": ["spam_bot", "advertisement"],
  "min_length": 5,
  "max_length": 1000,
  "time_window": 3600
}
```

### 8.2 Настройка логирования
```json
"log_level": "DEBUG",
"log_file": "logs/custom_log.log",
"log_format": "%(asctime)s - %(levelname)s - %(message)s"
```

### 8.3 Настройка таймаутов
```json
"timeouts": {
  "mcp_timeout": 10,
  "telegram_timeout": 30,
  "llm_timeout": 60
}
```

---

## Шаг 9: Безопасность

### 9.1 Хранение ключей
- Никогда не коммитите API ключи в Git
- Используйте переменные окружения для production
- Регулярно обновляйте ключи

### 9.2 Мониторинг безопасности
- Ведите логи всех действий
- Мониторьте использование API
- Регулярно проверяйте конфигурацию

### 9.3 Рекомендации
- Используйте HTTPS для MCP сервера
- Регулярно обновляйте зависимости
- Ограничьте доступ к конфигурационным файлам

---

## Поддержка

Если у вас возникли проблемы с настройкой:

1. Проверьте логи в `logs/telegram_agent.log`
2. Запустите health-check для диагностики
3. Проверьте версию Python и установленные пакеты
4. Создайте issue в репозитории проекта

---

## Быстрая проверка установки

```bash
# 1. Проверьте Python
python --version

# 2. Проверьте зависимости
pip list | grep -E "(openai|aiohttp|telethon)"

# 3. Проверьте конфигурацию
python -c "import json; print(json.load(open('config/config.json', 'r')))"

# 4. Запустите health-check
python -c "import asyncio; from src.agent import TelegramAgent; agent = TelegramAgent(); asyncio.run(agent.health_check())"

# 5. Запустите тесты
python -m unittest tests/test_agent.py
```
