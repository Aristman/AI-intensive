# Deploy.md - Руководство по развертыванию Telegram HTTP MCP Server

## Обзор

Это руководство описывает процесс развертывания Telegram HTTP MCP Server как локально, так и на удаленном сервере. Сервер может быть запущен на любом устройстве с Node.js 16+.

## Предварительные требования

- Node.js 16 или выше
- npm или yarn
- Аккаунт Telegram с созданным приложением на [my.telegram.org](https://my.telegram.org)
- (Опционально) Docker для контейнеризации
- (Опционально) PM2 для управления процессами

## Локальный запуск

### 1. Клонирование и установка

```bash
git clone <repository-url>
cd telegram_http_mcp
npm install
```

### 2. Настройка переменных окружения

Создайте файл `.env` в корневой директории:

```env
# Telegram API credentials
TG_APP_ID=your_app_id_here
TG_API_HASH=your_api_hash_here

# Server configuration
PORT=3000
HOST=localhost

# Session file path (optional)
TG_SESSION_FILE=./session.txt
```

### 3. Аутентификация в Telegram

```bash
npm run auth
```

Следуйте инструкциям:
1. Введите номер телефона
2. Введите пароль двухфакторной аутентификации (если включен)
3. Введите код подтверждения из Telegram

После успешной аутентификации будет создан файл `session.txt`.

### 4. Запуск сервера

```bash
npm start
```

Сервер будет доступен по адресу `http://localhost:3000`.

### 5. Проверка работоспособности

```bash
curl http://localhost:3000/health
```

Ожидаемый ответ:
```json
{"ok": true, "status": "ready"}
```

## Развертывание на VPS/Выделенном сервере

### Подготовка сервера

1. Обновите систему:
```bash
sudo apt update && sudo apt upgrade
```

2. Установите Node.js:
```bash
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
```

3. Установите необходимые инструменты:
```bash
sudo apt install git nginx certbot python3-certbot-nginx
```

### Клонирование проекта

```bash
git clone <repository-url>
cd telegram_http_mcp
npm install --production
```

### Настройка переменных окружения

```bash
nano .env
```

Содержимое файла `.env`:
```env
TG_APP_ID=your_app_id_here
TG_API_HASH=your_api_hash_here
PORT=3000
HOST=0.0.0.0
TG_SESSION_FILE=/path/to/secure/session.txt
```

### Аутентификация

```bash
npm run auth
```

> **Важно:** Выполните аутентификацию на сервере, где будет работать приложение, так как сессия привязана к устройству.

### Настройка SystemD (рекомендуется)

Создайте сервисный файл:

```bash
sudo nano /etc/systemd/system/telegram-mcp.service
```

Содержимое файла:
```ini
[Unit]
Description=Telegram HTTP MCP Server
After=network.target

[Service]
Type=simple
User=your-user
WorkingDirectory=/path/to/telegram_http_mcp
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

Активируйте и запустите сервис:

```bash
sudo systemctl daemon-reload
sudo systemctl enable telegram-mcp
sudo systemctl start telegram-mcp
```

Проверка статуса:
```bash
sudo systemctl status telegram-mcp
```

### Настройка Nginx (реверс-прокси)

```bash
sudo nano /etc/nginx/sites-available/telegram-mcp
```

Содержимое файла:
```nginx
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
```

Активируйте сайт:
```bash
sudo ln -s /etc/nginx/sites-available/telegram-mcp /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### Настройка SSL (Let's Encrypt)

```bash
sudo certbot --nginx -d your-domain.com
```

### Использование PM2 (альтернатива SystemD)

Установите PM2:
```bash
sudo npm install -g pm2
```

Создайте файл `ecosystem.config.js`:
```javascript
module.exports = {
  apps: [{
    name: 'telegram-mcp',
    script: 'server.js',
    env: {
      NODE_ENV: 'production'
    }
  }]
};
```

Запуск:
```bash
pm2 start ecosystem.config.js
pm2 save
pm2 startup
```

## Docker развертывание

### Dockerfile

Создайте `Dockerfile`:
```dockerfile
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

EXPOSE 3000

CMD ["npm", "start"]
```

### docker-compose.yml

```yaml
version: '3.8'
services:
  telegram-mcp:
    build: .
    ports:
      - "3000:3000"
    env_file:
      - .env
    volumes:
      - ./session.txt:/app/session.txt
    restart: unless-stopped
```

### Сборка и запуск

```bash
docker-compose up -d
```

### Аутентификация в Docker

```bash
docker-compose exec telegram-mcp npm run auth
```

## Мониторинг и логи

### Просмотр логов

SystemD:
```bash
sudo journalctl -u telegram-mcp -f
```

PM2:
```bash
pm2 logs telegram-mcp
```

Docker:
```bash
docker-compose logs -f
```

### Мониторинг здоровья

```bash
curl https://your-domain.com/health
```

## Безопасность

### Firewall

```bash
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'
sudo ufw --force enable
```

### Защита переменных окружения

- Не коммитьте `.env` файл в Git
- Используйте сильные пароли
- Регулярно обновляйте зависимости

### Резервное копирование

Создайте скрипт для бэкапа сессии:

```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
cp session.txt session_backup_$DATE.txt
echo "Backup created: session_backup_$DATE.txt"
```

## Troubleshooting

### Проблемы с аутентификацией

- Убедитесь, что `TG_APP_ID` и `TG_API_HASH` корректны
- Проверьте, что сессия не истекла (повторите аутентификацию)
- Проверьте права на файл сессии

### Сервер не запускается

- Проверьте логи: `sudo journalctl -u telegram-mcp -n 50`
- Убедитесь, что порт 3000 свободен
- Проверьте переменные окружения

### Проблемы с подключением

- Проверьте доступность Telegram API
- Убедитесь, что сервер имеет доступ к интернету
- Проверьте настройки firewall

## Обновление

### Автоматическое обновление

```bash
#!/bin/bash
cd /path/to/telegram_http_mcp
git pull
npm install
sudo systemctl restart telegram-mcp
```

### Ручное обновление

```bash
sudo systemctl stop telegram-mcp
git pull
npm install
sudo systemctl start telegram-mcp
```

## Производственная конфигурация

Для продакшена рекомендуется:

- Использовать домен с SSL
- Настроить логирование в файлы
- Добавить мониторинг (например, Prometheus + Grafana)
- Настроить ротацию логов
- Использовать контейнеры для изоляции
