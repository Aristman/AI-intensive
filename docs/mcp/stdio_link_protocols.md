### 1. Прямое STDIO (только для локальных серверов)

**Когда использовать**: Если MCP-сервер запущен на той же машине, что и клиент.

**Как работает**: Клиент напрямую запускает процесс сервера и общается с ним через стандартные потоки ввода/вывода.

```python
import subprocess
import json

# Запускаем серверный процесс напрямую
process = subprocess.Popen(
    ['path/to/your/mcp/server'],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1  # построчная буферизация
)

# Общаемся через stdin/stdout
def send_message(method, params):
    message = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": method,
        "params": params
    }
    process.stdin.write(json.dumps(message) + '\n')
    process.stdin.flush()

# Читаем ответ
response_line = process.stdout.readline()
response = json.loads(response_line)
```

---

### 2. SSE (Server-Sent Events)

**Когда использовать**: Для удалённых серверов, когда сервер может отправлять события клиенту.

**Как работает**: Клиент подключается к HTTP endpoint сервера и получает события через long-lived соединение.

```python
import requests
import json

# Подключаемся к SSE endpoint сервера
url = "http://your-vps-ip:8080/sse"
headers = {'Accept': 'text/event-stream'}

response = requests.get(url, headers=headers, stream=True)

for line in response.iter_lines():
    if line:
        # SSE сообщение выглядит как: data: {"json": "data"}
        if line.startswith(b'data: '):
            json_data = json.loads(line[6:])  # убираем "data: "
            # обрабатываем MCP сообщение
            print("Received:", json_data)
```

---

### 3. WebSocket

**Когда использовать**: Для двусторонней реальном времени связи между клиентом и сервером.

**Как работает**: Устанавливается постоянное WebSocket соединение, через которое обе стороны могут отправлять сообщения.

```python
import asyncio
import websockets
import json

async def mcp_websocket_client():
    uri = "ws://your-vps-ip:8080/ws"
    
    async with websockets.connect(uri) as websocket:
        # Отправляем initialize сообщение
        init_message = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024.11.05",
                "capabilities": {},
                "clientInfo": {"name": "WebSocket Client", "version": "1.0.0"}
            }
        }
        await websocket.send(json.dumps(init_message))
        
        # Слушаем сообщения
        async for message in websocket:
            mcp_message = json.loads(message)
            print("Received:", mcp_message)
            
            # Здесь обработка различных типов сообщений MCP

# Запускаем клиента
asyncio.get_event_loop().run_until_complete(mcp_websocket_client())
```

---

### 4. HTTP Long-Polling

**Когда использовать**: Когда WebSocket или SSE недоступны, но нужна почти реальном времени связь.

**Как работает**: Клиент отправляет HTTP запрос и сервер держит его открытым, пока не появится сообщение.

```python
import requests
import json

def long_poll_client():
    base_url = "http://your-vps-ip:8080"
    
    # Регистрируем клиента
    response = requests.post(f"{base_url}/register", json={
        "clientInfo": {"name": "HTTP Client", "version": "1.0.0"}
    })
    client_id = response.json()["clientId"]
    
    # Бесконечный цикл long-polling
    while True:
        try:
            response = requests.get(f"{base_url}/messages/{client_id}", timeout=30)
            if response.status_code == 200:
                messages = response.json()
                for message in messages:
                    # Обрабатываем MCP сообщение
                    handle_mcp_message(message)
            
            # Отправляем наши сообщения (если есть)
            if has_messages_to_send():
                requests.post(f"{base_url}/send/{client_id}", json=get_outgoing_messages())
                
        except requests.exceptions.Timeout:
            # Таймаут - это нормально для long-polling
            continue
```

---

### 5. HTTP REST API (для простых сценариев)

**Когда использовать**: Для простых запросов, не требующих постоянного соединения.

**Как работает**: Клиент отправляет HTTP запросы для выполнения операций.

```python
import requests
import json

def call_mcp_tool(tool_name, arguments):
    response = requests.post(
        "http://your-vps-ip:8080/tools/call",
        json={
            "tool": tool_name,
            "arguments": arguments
        }
    )
    return response.json()

def read_resource(resource_uri):
    response = requests.get(
        f"http://your-vps-ip:8080/resources/read",
        params={"uri": resource_uri}
    )
    return response.json()

# Использование
result = call_mcp_tool("search", {"query": "python mcp", "limit": 10})
print(result)
```

---

### 6. gRPC (альтернативный высокопроизводительный вариант)

**Когда использовать**: Для высокопроизводительных сценариев с strict API контрактами.

```python
# proto/mcp.proto
syntax = "proto3";

service MCPService {
    rpc Initialize(InitializeRequest) returns (InitializeResponse);
    rpc CallTool(ToolRequest) returns (ToolResponse);
    rpc ReadResource(ResourceRequest) returns (ResourceResponse);
    rpc StreamMessages(stream ClientMessage) returns (stream ServerMessage);
}

# Клиентская реализация
import grpc
from proto import mcp_pb2, mcp_pb2_grpc

def run():
    channel = grpc.insecure_channel('your-vps-ip:50051')
    stub = mcp_pb2_grpc.MCPServiceStub(channel)
    
    # Инициализация
    response = stub.Initialize(mcp_pb2.InitializeRequest(
        protocol_version="2024.11.05",
        client_info=mcp_pb2.ClientInfo(name="gRPC Client", version="1.0.0")
    ))
    
    # Вызов инструмента
    tool_response = stub.CallTool(mcp_pb2.ToolRequest(
        name="search",
        arguments='{"query": "python", "limit": 5}'
    ))
```

---

### Какой вариант выбрать?

1. **Локальный сервер** → Прямое STDIO
2. **Реальное время, двусторонняя связь** → WebSocket
3. **Сервер отправляет события** → SSE
4. **Простая запрос-ответ модель** → HTTP REST API
5. **Высокая производительность** → gRPC
6. **Ограниченная среда** → HTTP Long-Polling

### Важные замечания:

1. **Безопасность**: Для удалённых соединений обязательно используйте HTTPS/WSS вместо HTTP/WS
2. **Аутентификация**: Добавьте механизмы аутентификации (API keys, JWT tokens)
3. **Сериализация**: MCP использует JSON, убедитесь в правильной сериализации/десериализации
4. **Таймауты**: Реализуйте обработку таймаутов и переподключения
5. **Протокол**: Независимо от транспорта, сообщения должны следовать спецификации MCP JSON-RPC

Для начала рекомендую WebSocket подход, так как он обеспечивает полноценную двустороннюю связь и хорошо поддерживается в большинстве языков программирования.