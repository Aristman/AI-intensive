#!/usr/bin/env python3
import sys
import os
import asyncio
import json
from typing import Any, Dict, Optional

from .config import Config, validate_config
from .utils import setup_telegram_client
from .tools import ToolsHandler
from .resources import list_resources, read_resource


class MCPServer:
    def __init__(self) -> None:
        self.name = Config.name
        self.version = Config.version
        self.telegram_cfg = Config.telegram
        self.client = None  # type: ignore
        self.tools: Optional[ToolsHandler] = None
        self.initialized = False
        self._ready_event = asyncio.Event()

    async def start(self) -> None:
        # Logs must go to stderr
        print("MCP Python server starting (stdio)", file=sys.stderr)
        validate_config()
        # Initialize Telegram client in background
        asyncio.create_task(self._init_telegram())
        # Start serve loop
        await self._serve_stdio()

    async def _init_telegram(self) -> None:
        try:
            t = self.telegram_cfg
            api_id = t.get("api_id")
            api_hash = t.get("api_hash")
            phone_number = t.get("phone_number")
            bot_token = t.get("bot_token")
            session_file = t.get("session_file")
            self.client = await setup_telegram_client(api_id, api_hash, phone_number, bot_token, session_file)
            self.tools = ToolsHandler(self.client)
            print("Telegram client ready, tools registered.", file=sys.stderr)
            try:
                self._ready_event.set()
            except Exception:
                pass
        except Exception as e:
            print(f"Failed to initialize Telegram client in background: {e}", file=sys.stderr)

    async def _serve_stdio(self) -> None:
        reader = AsyncStdioReader()
        writer = AsyncStdioWriter()
        while True:
            msg = await reader.read_message()
            if msg is None:
                break
            try:
                response = await self._handle_request(msg)
            except Exception as e:
                response = self._error_response(msg, code=-32000, message=str(e))
            if response is not None:
                await writer.write_message(response)

    async def _handle_request(self, req: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        method = req.get("method")
        id_ = req.get("id")
        params = req.get("params") or {}

        # initialize
        if method == "initialize":
            self.initialized = True
            # respond with server info and capabilities
            return {
                "jsonrpc": "2.0",
                "id": id_,
                "result": {
                    "protocolVersion": "2024-09-18",
                    "serverInfo": {"name": self.name, "version": self.version},
                    "capabilities": {
                        "tools": {},
                        "resources": {},
                        "prompts": {}
                    }
                }
            }

        # list tools
        if method in ("tools/list", "list_tools"):
            tools = []
            if self.tools is not None:
                tools = await self.tools.list()
            return {"jsonrpc": "2.0", "id": id_, "result": {"tools": tools}}

        # call tool
        if method in ("tools/call", "call_tool"):
            # Wait for readiness if tools not yet ready
            if self.tools is None:
                try:
                    await asyncio.wait_for(self._ready_event.wait(), timeout=20.0)
                except Exception:
                    pass
            if self.tools is None:
                text = json.dumps({"error": "Tools not ready"}, ensure_ascii=False)
                return {"jsonrpc": "2.0", "id": id_, "result": {"content": [{"type": "text", "text": text}]}}
            name = params.get("name")
            args = params.get("arguments") or {}
            raw = await self.tools.call(name, args)
            text = raw if isinstance(raw, str) else json.dumps(raw, ensure_ascii=False)
            return {"jsonrpc": "2.0", "id": id_, "result": {"content": [{"type": "text", "text": text}]}}

        # resources.list
        if method in ("resources/list", "list_resources"):
            items = await list_resources()
            return {"jsonrpc": "2.0", "id": id_, "result": {"resources": items}}

        # resources.read
        if method in ("resources/read", "read_resource"):
            uri = (params or {}).get("uri")
            res = await read_resource(uri)
            # follow Node.js compatibility: return contents array if present
            if isinstance(res, dict) and isinstance(res.get("contents"), list):
                return {"jsonrpc": "2.0", "id": id_, "result": {"contents": res["contents"]}}
            return {"jsonrpc": "2.0", "id": id_, "result": {"contents": [{"uri": uri, "mimeType": "application/json", "text": json.dumps(res)}]}}

        # unknown method
        return self._error_response(req, code=-32601, message="Method not found")

    def _error_response(self, req: Dict[str, Any], code: int, message: str) -> Dict[str, Any]:
        return {"jsonrpc": "2.0", "id": req.get("id"), "error": {"code": code, "message": message}}


class AsyncStdioReader:
    async def read_message(self) -> Optional[Dict[str, Any]]:
        # Read headers until blank line
        headers: Dict[str, str] = {}
        header_bytes = bytearray()
        while True:
            line = await asyncio.get_event_loop().run_in_executor(None, sys.stdin.buffer.readline)
            if not line:
                return None
            header_bytes.extend(line)
            if line in (b"\r\n", b"\n"):
                break
            # parse header line
            try:
                s = line.decode("utf-8", errors="ignore").strip()
                if ":" in s:
                    k, v = s.split(":", 1)
                    headers[k.strip().lower()] = v.strip()
            except Exception:
                pass
        content_length = int(headers.get("content-length", "0"))
        body = b""
        to_read = content_length
        while to_read > 0:
            chunk = await asyncio.get_event_loop().run_in_executor(None, sys.stdin.buffer.read, to_read)
            if not chunk:
                break
            body += chunk
            to_read -= len(chunk)
        if not body:
            return None
        try:
            return json.loads(body.decode("utf-8"))
        except Exception as e:
            print(f"Failed to parse JSON-RPC body: {e}", file=sys.stderr)
            return None


class AsyncStdioWriter:
    async def write_message(self, msg: Dict[str, Any]) -> None:
        data = json.dumps(msg, ensure_ascii=False).encode("utf-8")
        header = f"Content-Length: {len(data)}\r\n\r\n".encode("ascii")
        await asyncio.get_event_loop().run_in_executor(None, sys.stdout.buffer.write, header)
        await asyncio.get_event_loop().run_in_executor(None, sys.stdout.buffer.write, data)
        await asyncio.get_event_loop().run_in_executor(None, sys.stdout.buffer.flush)


async def main() -> None:
    server = MCPServer()
    await server.start()


if __name__ == "__main__":
    # Ensure unbuffered stdout/stderr in case Python is started without -u
    try:
        sys.stdout.reconfigure(line_buffering=False)
        sys.stderr.reconfigure(line_buffering=True)
    except Exception:
        pass
    asyncio.run(main())
