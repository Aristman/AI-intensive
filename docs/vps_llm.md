# Инструкция по развертыванию TinyLlama-1.1B на VPS

### 1. **Подготовка сервера**
```bash
# Обновление системы
sudo apt update && sudo apt upgrade -y

# Установка необходимых пакетов
sudo apt install -y python3-pip python3-venv git wget build-essential
```

### 2. **Создание виртуального окружения**
```bash
# Создание директории для проекта
mkdir tinylama-app && cd tinylama-app

# Создание виртуального окружения
python3 -m venv venv
source venv/bin/activate
```

### 3. **Установка зависимостей**
```bash
# Установка PyTorch для CPU (оптимизированная версия)
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

# Установка дополнительных библиотек
pip install transformers accelerate sentencepiece uvicorn fastapi
```

### 4. **Загрузка модели TinyLlama-1.1B**
Создайте файл `download_model.py`:
```python
from transformers import AutoModelForCausalLM, AutoTokenizer

model_name = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
print("Загрузка токенизатора...")
tokenizer = AutoTokenizer.from_pretrained(model_name)
print("Загрузка модели...")
model = AutoModelForCausalLM.from_pretrained(
    model_name,
    device_map="auto",
    torch_dtype="auto"
)
print("Модель успешно загружена!")
```

Запустите загрузку:
```bash
python download_model.py
```

### 5. **Создание API-сервера**
Создайте файл `app.py`:
```python
from fastapi import FastAPI
from transformers import AutoModelForCausalLM, AutoTokenizer
import uvicorn
import torch

app = FastAPI()

# Загрузка модели и токенизатора
model_name = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
tokenizer = AutoTokenizer.from_pretrained(model_name)
model = AutoModelForCausalLM.from_pretrained(
    model_name,
    device_map="auto",
    torch_dtype="auto"
)

@app.post("/generate")
async def generate_text(prompt: str, max_length: int = 100):
    # Форматирование промпта для TinyLlama
    formatted_prompt = f"<|system|>\nYou are a helpful assistant.</s>\n<|user|>\n{prompt}</s>\n<|assistant|>\n"
    
    # Токенизация
    inputs = tokenizer(formatted_prompt, return_tensors="pt")
    
    # Генерация
    with torch.no_grad():
        outputs = model.generate(
            **inputs,
            max_length=max_length,
            temperature=0.7,
            do_sample=True,
            pad_token_id=tokenizer.eos_token_id
        )
    
    # Декодирование
    response = tokenizer.decode(outputs[0], skip_special_tokens=True)
    
    # Извлечение только ответа ассистента
    assistant_response = response.split("<|assistant|>")[-1].strip()
    
    return {"response": assistant_response}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

### 6. **Запуск сервера**
```bash
# Запуск напрямую
python app.py

# Или запуск в фоновом режиме с nohup
nohup python app.py > server.log 2>&1 &
```

### 7. **Тестирование API**
```bash
curl -X POST "http://localhost:8000/generate" -H "Content-Type: application/json" -d '{"prompt": "Что такое искусственный интеллект?", "max_length": 150}'

Invoke-WebRequest -Uri "http://158.160.107.227:8000/generate" -Method POST -ContentType "application/json" -Body '{"prompt": "Что такое искусственный интеллект?", "max_length": 150}'
```

### 8. **Оптимизация для малопроизводительных серверов**
Создайте оптимизированную версию `app_optimized.py`:
```python
from fastapi import FastAPI
from transformers import AutoModelForCausalLM, AutoTokenizer, pipeline
import uvicorn

app = FastAPI()

# Использование pipeline для оптимизации
model_name = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
pipe = pipeline(
    "text-generation",
    model=model_name,
    device="cpu",
    torch_dtype="auto"
)

@app.post("/generate")
async def generate_text(prompt: str, max_length: int = 100):
    formatted_prompt = f"<|system|>\nYou are a helpful assistant.</s>\n<|user|>\n{prompt}</s>\n<|assistant|>\n"
    
    # Генерация с помощью pipeline
    result = pipe(
        formatted_prompt,
        max_length=max_length,
        temperature=0.7,
        do_sample=True,
        pad_token_id=pipe.tokenizer.eos_token_id
    )
    
    response = result[0]['generated_text']
    assistant_response = response.split("<|assistant|>")[-1].strip()
    
    return {"response": assistant_response}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000, workers=1)
```

### 9. **Создание службы systemd для автозапуска**
Создайте файл `/etc/systemd/system/tinylama.service`:
```ini
[Unit]
Description=TinyLlama API Service
After=network.target

[Service]
User=root
WorkingDirectory=/root/tinylama-app
Environment="PATH=/root/tinylama-app/venv/bin"
ExecStart=/root/tinylama-app/venv/bin/python /root/tinylama-app/app_optimized.py
Restart=always

[Install]
WantedBy=multi-user.target
```

Активируйте службу:
```bash
sudo systemctl daemon-reload
sudo systemctl start tinylama
sudo systemctl enable tinylama
```

### 10. **Мониторинг и управление**
```bash
# Проверка статуса службы
sudo systemctl status tinylama

# Просмотр логов
journalctl -u tinylama -f

# Остановка службы
sudo systemctl stop tinylama
```

### Дополнительные рекомендации:

1. **Оптимизация памяти**:
    - Модель занимает около 2.2 ГБ в оперативной памяти
    - Для экономии памяти можно использовать квантование:
   ```python
   model = AutoModelForCausalLM.from_pretrained(
       model_name,
       device_map="auto",
       load_in_4bit=True,  # 4-битное квантование
       bnb_4bit_compute_dtype=torch.float16
   )
   ```

2. **Безопасность**:
   ```bash
   # Открытие порта в фаерволе
   sudo ufw allow 8000
   sudo ufw enable
   ```

3. **Производительность**:
    - Для увеличения скорости ответа уменьшите `max_length`
    - Используйте кэширование запросов
    - Рассмотрите использование более легкого веб-сервера (например, `waitress`)

4. **Резервное копирование**:
    - Модель занимает около 2.2 ГБ на диске
    - Регулярно делайте бэкапы важных данных

Эта инструкция позволяет развернуть TinyLlama-1.1B на VPS с 8 ГБ RAM, оставляя достаточно памяти для операционной системы и других процессов.


# Инструкция по созданию OpenAI-совместимого API для TinyLlama-1.1B

Создадим API, совместимый с форматом запросов OpenAI, чтобы можно было использовать стандартные клиентские библиотеки.

## 1. Установка дополнительных зависимостей

```bash
pip install pydantic
```

## 2. Создание OpenAI-совместимого API

Создайте файл `openai_app.py`:

```python
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from transformers import AutoModelForCausalLM, AutoTokenizer, TextIteratorStreamer
import uvicorn
import torch
from threading import Thread
from typing import List, Optional, Dict, Any
import time
import shortuuid
import json

app = FastAPI(title="TinyLlama OpenAI-Compatible API")

# Модели запросов и ответов, совместимые с OpenAI API
class ChatMessage(BaseModel):
    role: str
    content: str

class ChatCompletionRequest(BaseModel):
    model: str = "TinyLlama-1.1B-Chat"
    messages: List[ChatMessage]
    temperature: float = 0.7
    top_p: float = 0.9
    max_tokens: int = 512
    stream: bool = False

class UsageInfo(BaseModel):
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int

class ChatCompletionResponseChoice(BaseModel):
    index: int
    message: ChatMessage
    finish_reason: str

class ChatCompletionResponse(BaseModel):
    id: str
    object: str = "chat.completion"
    created: int
    model: str
    choices: List[ChatCompletionResponseChoice]
    usage: UsageInfo

class ModelCard(BaseModel):
    id: str
    object: str = "model"
    created: int
    owned_by: str = "local"

class ModelList(BaseModel):
    object: str = "list"
    data: List[ModelCard]

# Загрузка модели и токенизатора
model_name = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
print("Loading tokenizer...")
tokenizer = AutoTokenizer.from_pretrained(model_name)
print("Loading model...")
model = AutoModelForCausalLM.from_pretrained(
    model_name,
    device_map="auto",
    torch_dtype="auto",
    low_cpu_mem_usage=True
)
print("Model loaded successfully!")

# Форматирование промпта для TinyLlama
def format_prompt(messages: List[ChatMessage]) -> str:
    formatted_prompt = ""
    
    for message in messages:
        if message.role == "system":
            formatted_prompt += f"<|system|>\n{message.content}</s>\n"
        elif message.role == "user":
            formatted_prompt += f"<|user|>\n{message.content}</s>\n"
        elif message.role == "assistant":
            formatted_prompt += f"<|assistant|>\n{message.content}</s>\n"
    
    # Добавляем тег для начала ответа ассистента
    formatted_prompt += "<|assistant|>\n"
    
    return formatted_prompt

# Эндпоинт для получения списка моделей
@app.get("/v1/models", response_model=ModelList)
async def list_models():
    model_card = ModelCard(
        id="TinyLlama-1.1B-Chat",
        created=int(time.time()),
        owned_by="local"
    )
    return ModelList(data=[model_card])

# Эндпоинт для чат-запросов
@app.post("/v1/chat/completions", response_model=ChatCompletionResponse)
async def create_chat_completion(request: ChatCompletionRequest):
    try:
        # Форматируем промпт
        prompt = format_prompt(request.messages)
        
        # Токенизируем промпт
        inputs = tokenizer(prompt, return_tensors="pt")
        
        # Генерация ответа
        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                max_new_tokens=request.max_tokens,
                temperature=request.temperature,
                top_p=request.top_p,
                do_sample=True,
                pad_token_id=tokenizer.eos_token_id
            )
        
        # Декодируем ответ
        response_text = tokenizer.decode(outputs[0], skip_special_tokens=True)
        
        # Извлекаем только ответ ассистента
        assistant_response = response_text.split("<|assistant|>")[-1].strip()
        
        # Подсчет токенов (упрощенный)
        prompt_tokens = len(tokenizer.encode(prompt))
        completion_tokens = len(tokenizer.encode(assistant_response))
        
        # Создаем ответ
        response = ChatCompletionResponse(
            id=f"chatcmpl-{shortuuid.random()}",
            created=int(time.time()),
            model=request.model,
            choices=[
                ChatCompletionResponseChoice(
                    index=0,
                    message=ChatMessage(
                        role="assistant",
                        content=assistant_response
                    ),
                    finish_reason="stop"
                )
            ],
            usage=UsageInfo(
                prompt_tokens=prompt_tokens,
                completion_tokens=completion_tokens,
                total_tokens=prompt_tokens + completion_tokens
            )
        )
        
        return response
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Эндпоинт для проверки здоровья
@app.get("/health")
async def health_check():
    return {"status": "healthy"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

## 3. Создание службы systemd

Создайте файл `/etc/systemd/system/tinylama-openai.service`:

```ini
[Unit]
Description=TinyLlama OpenAI API Service
After=network.target

[Service]
User=root
WorkingDirectory=/root/tinylama-app
Environment="PATH=/root/tinylama-app/venv/bin"
ExecStart=/root/tinylama-app/venv/bin/python /root/tinylama-app/openai_app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Активируйте службу:

```bash
sudo systemctl daemon-reload
sudo systemctl start tinylama-openai
sudo systemctl enable tinylama-openai
```

## 4. Тестирование API

### Получение списка моделей:

```bash
curl http://localhost:8000/v1/models
```

### Отправка запроса в формате OpenAI:

```bash
curl -X POST "http://localhost:8000/v1/chat/completions" -H "Content-Type: application/json" -d '{
  "model": "TinyLlama-1.1B-Chat",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Что такое искусственный интеллект?"}
  ],
  "temperature": 0.7,
  "max_tokens": 150
}'
```

### Использование с клиентскими библиотеками OpenAI:

Если вы используете Python, вы можете настроить клиент OpenAI для работы с вашим API:

```python
import openai

# Настройка клиента для использования вашего API
client = openai.OpenAI(
    base_url="http://your-server-ip:8000/v1",
    api_key="sk-no-key-required"  # Можно указать любой ключ
)

# Отправка запроса
response = client.chat.completions.create(
    model="TinyLlama-1.1B-Chat",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Что такое искусственный интеллект?"}
    ],
    temperature=0.7,
    max_tokens=150
)

print(response.choices[0].message.content)
```

## 5. Дополнительные настройки

### Добавление CORS middleware:

```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

### Добавление аутентификации:

```python
from fastapi import Depends, Header
from typing import Annotated

async def verify_token(authorization: Annotated[str, Header()] = None):
    if authorization is None or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid token")
    
    token = authorization[7:]
    if token != "your-secret-token":
        raise HTTPException(status_code=401, detail="Invalid token")
    
    return token

# Добавьте зависимость к эндпоинтам:
@app.post("/v1/chat/completions", response_model=ChatCompletionResponse)
async def create_chat_completion(
    request: ChatCompletionRequest, 
    token: str = Depends(verify_token)
):
    # ваш код
```

## 6. Мониторинг и логирование

Добавьте логирование для отслеживания запросов:

```python
import logging

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("api.log"),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

# В эндпоинте добавьте логирование:
logger.info(f"Received request: {request}")
```

Этот API теперь совместим с форматом запросов OpenAI, что позволяет использовать его со стандартными клиентскими библиотеками и инструментами.

Отлично! Я создал полную документацию для вашего TinyLlama OpenAI-совместимого API. Вот что было создано:

📄 Основные файлы:

1. README.md - Подробная документация с:
   •  Обзором проекта
   •  Инструкциями по установке
   •  Описанием всех API эндпоинтов
   •  Примерами запросов и ответов
   •  Руководством по устранению неполадок
2. requirements.txt - Список всех зависимостей Python
3. test_api.py - Тестовый скрипт для проверки работоспособности API
4. Dockerfile - Для контейнеризации приложения
5. docker-compose.yml - Для удобного запуска с Docker Compose

🚀 Ключевые особенности API:

Основной эндпоинт:
•  POST /v1/chat/completions - OpenAI-совместимый API для чат-диалогов

Параметры запроса:
•  model: "TinyLlama-1.1B-Chat" (по умолчанию)
•  messages: массив сообщений с ролями system/user/assistant
•  temperature: 0.7 (контроль случайности)
•  max_tokens: автоматически или заданное значение
•  top_p: 0.9 (nucleus sampling)
•  stream: false (потоковая передача пока не поддерживается)

Дополнительный эндпоинт:
•  POST /v1/token_count - подсчет токенов в запросе

Технические ограничения:
•  Максимальный контекст: 2048 токенов
•  Модель: TinyLlama/TinyLlama-1.1B-Chat-v1.0 (1.1B параметров)
•  Формат промптов: ChatML-подобный

📝 Примеры использования включают:
•  cURL команды
•  Python с requests
•  JavaScript/Node.js
•  Использование с официальным OpenAI Python SDK

Теперь у вас есть полная документация для развертывания и использования вашего TinyLlama API сервера!