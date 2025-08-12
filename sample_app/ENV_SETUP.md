# Настройка переменных окружения

Для работы приложения необходимо настроить файл `.env` в корневой директории проекта. Этот файл содержит конфиденциальные данные и не должен попадать в систему контроля версий.

## Создание файла .env

1. Создайте файл `.env` в корневой директории проекта (рядом с `pubspec.yaml`)
2. Добавьте в него следующие переменные:

```env
# DeepSeek API Configuration
DEEPSEEK_API_KEY=your_deepseek_api_key_here
DEEPSEEK_BASE_URL=https://api.deepseek.com

# YandexGPT API Configuration (опционально)
# YANDEX_API_KEY=your_yandex_api_key_here
# YANDEX_FOLDER_ID=your_yandex_folder_id_here
# YANDEX_GPT_BASE_URL=https://llm.api.cloud.yandex.net

# App Defaults
DEFAULT_MODEL=deepseek-chat
DEFAULT_SYSTEM_PROMPT=You are a helpful AI assistant.
```

## Описание переменных

### Обязательные переменные

- `DEEPSEEK_API_KEY` - API ключ для доступа к DeepSeek API
- `DEEPSEEK_BASE_URL` - Базовый URL для DeepSeek API (по умолчанию: `https://api.deepseek.com`)

### Опциональные переменные

- `YANDEX_API_KEY` - API ключ для доступа к YandexGPT (если используется)
- `YANDEX_FOLDER_ID` - ID каталога Yandex Cloud (если используется YandexGPT)
- `YANDEX_GPT_BASE_URL` - Базовый URL для YandexGPT API (по умолчанию: `https://llm.api.cloud.yandex.net`)
- `DEFAULT_MODEL` - Модель по умолчанию (по умолчанию: `deepseek-chat`)
- `DEFAULT_SYSTEM_PROMPT` - Системный промпт по умолчанию

## Безопасность

- **НИКОГДА** не коммитьте файл `.env` в систему контроля версий
- Добавьте `.env` в `.gitignore`
- Храните резервные копии ваших API ключей в безопасном месте

## Валидация

При запуске приложения выполняется проверка наличия обязательных переменных. Если какая-то из обязательных переменных отсутствует, приложение отобразит сообщение об ошибке.

## Пример полного файла .env

```env
# DeepSeek API Configuration
DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
DEEPSEEK_BASE_URL=https://api.deepseek.com

# YandexGPT API Configuration
YANDEX_API_KEY=AQVNxxxxxxxxxxxxxxxxxxxxxx
YANDEX_FOLDER_ID=b1gxxxxxxxxxxxxxxxxxxxx
YANDEX_GPT_BASE_URL=https://llm.api.cloud.yandex.net

# App Defaults
DEFAULT_MODEL=deepseek-chat
DEFAULT_SYSTEM_PROMPT=You are a helpful AI assistant that responds in Russian.
```
