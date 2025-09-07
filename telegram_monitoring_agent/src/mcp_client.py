#!/usr/bin/env python3
"""
MCP Client for Telegram operations using STDIO transport with SSH support
"""

import asyncio
import json
import logging
from typing import Dict, Any, Optional, List
import subprocess
import sys
import os
from pathlib import Path

class MCPClient:
    def __init__(self, command: str = None, env_vars: Optional[Dict[str, str]] = None,
                 transport: str = "stdio", ssh_config: Optional[Dict[str, Any]] = None,
                 http_config: Optional[Dict[str, Any]] = None):
        self.command = command or self._get_default_command()
        self.env_vars = env_vars or {}
        self.transport = transport
        self.ssh_config = ssh_config or {}
        self.http_config = http_config or {}
        self.process: Optional[subprocess.Popen] = None
        self.logger = logging.getLogger(__name__)

        # Request ID counter for JSON-RPC
        self.request_id = 1

        # Setup environment variables
        self._setup_environment()

        # Internal state
        self._initialized: bool = False
        self._stderr_task: Optional[asyncio.Task] = None
        # Create readiness event immediately so callers can await it reliably
        try:
            self._ready_event: asyncio.Event = asyncio.Event()
        except Exception:
            # Fallback if no loop yet; will be replaced lazily in start()
            self._ready_event = None  # type: ignore
        # Serialize all stdio I/O to prevent interleaved frames
        self._io_lock: asyncio.Lock = asyncio.Lock()
        # Prevent concurrent start() from spawning multiple processes
        self._start_lock: asyncio.Lock = asyncio.Lock()
        # Persistent receive buffer to store any extra bytes between calls
        self._rx_buffer: bytearray = bytearray()

    def _get_default_command(self) -> str:
        """Get the default command to run the Telegram MCP server"""
        # Use Python implementation: run module mcp_servers.telegram_mcp_server_py.main with unbuffered stdio
        # Ensures stdout is reserved for MCP frames as in the Node.js version.
        py = sys.executable or "python"
        return f"\"{py}\" -u -m mcp_servers.telegram_mcp_server_py.main"

    def _setup_environment(self):
        """Setup environment variables for telegram-mcp"""
        # Add current PATH to ensure telegram-mcp is found
        if 'PATH' not in self.env_vars:
            self.env_vars['PATH'] = os.environ.get('PATH', '')

        # Add HOME if not present
        if 'HOME' not in self.env_vars:
            self.env_vars['HOME'] = os.environ.get('HOME', str(Path.home()))

        # Copy all environment variables and update with custom ones
        self.full_env = os.environ.copy()
        self.full_env.update(self.env_vars)

    def _build_ssh_command(self) -> List[str]:
        """Build SSH command for remote execution"""
        ssh_cmd = ["ssh"]

        if self.ssh_config.get("port") and self.ssh_config["port"] != 22:
            ssh_cmd.extend(["-p", str(self.ssh_config["port"])])

        if self.ssh_config.get("key_path"):
            key_path = os.path.expanduser(self.ssh_config["key_path"])
            ssh_cmd.extend(["-i", key_path])

        # Add other SSH options for security and reliability
        ssh_cmd.extend([
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3"
        ])

        # Add user@host
        user_host = f"{self.ssh_config['user']}@{self.ssh_config['host']}"
        ssh_cmd.append(user_host)

        # Build remote command with exported env vars and run via bash -lc
        remote_cmd = self.ssh_config.get("remote_command", "telegram-mcp")

        # Prepare env exports from self.env_vars (escape quotes and backslashes)
        exports = []
        for k, v in (self.env_vars or {}).items():
            try:
                val = str(v).replace('\\', r'\\').replace('"', r'\"')
            except Exception:
                val = str(v)
            exports.append(f'{k}="{val}"')
        export_prefix = f"export {' '.join(exports)}; " if exports else ""

        shell_cmd = f"{export_prefix}exec {remote_cmd}"
        # Use non-interactive, non-login shell without profiles to avoid noisy stdout from rc files
        ssh_cmd.extend(["bash", "--noprofile", "--norc", "-lc", shell_cmd])

        return ssh_cmd

    async def __aenter__(self):
        await self.start()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.stop()

    async def _wait_ready(self, timeout: float = 20.0) -> None:
        """Wait until server readiness marker observed on stderr or until timeout.

        This prevents racing initialize/calls before the server (Telegram client/tools) is ready.
        """
        try:
            if self._ready_event:
                self.logger.debug(f"Waiting for server readiness marker up to {timeout}s...")
                await asyncio.wait_for(self._ready_event.wait(), timeout=timeout)
        except Exception:
            # Best-effort: continue
            pass

    async def start(self):
        """Start the MCP server process"""
        try:
            # Ensure only one start routine runs at a time
            async with self._start_lock:
                # If already started, nothing to do
                if self.transport == "stdio" and self.process is not None and (self.process.poll() is None):
                    return
            if self.transport == "http":
                self.logger.info("Using HTTP transport - no process needed")
                return
            elif self.transport == "stdio":
                if self.ssh_config.get("enabled", False):
                    # Use SSH tunneling
                    self.logger.info(f"Starting MCP server via SSH tunnel: {self.ssh_config['host']}")
                    cmd = self._build_ssh_command()
                else:
                    # Local STDIO
                    self.logger.info(f"Starting local MCP server process: {self.command}")
                    # Resolve repo root and absolute script path
                    repo_root = Path(__file__).parent.parent.parent
                    # If command is a string like "node <path>", convert to argv and absolutize script path
                    cmd_str = str(self.command)
                    if cmd_str.lower().startswith("node "):
                        script = cmd_str.split(" ", 1)[1].strip().strip('"')
                        script_path = Path(script)
                        if not script_path.is_absolute():
                            script_path = (repo_root / script_path).resolve()
                        cmd = ["node", str(script_path)]
                    else:
                        # Fallback: run via shell-style split but still set cwd to repo_root
                        import shlex
                        cmd = shlex.split(cmd_str)

                # Start the process
                self.process = subprocess.Popen(
                    cmd,
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    env=self.full_env,
                    text=False,  # binary mode for LSP-style framing
                    bufsize=0,
                    cwd=str(Path(__file__).parent.parent.parent)
                )

                self.logger.info("MCP server process started successfully")

                # Give the server time to initialize (npx may install on first run)
                await asyncio.sleep(2.0)

                # Start background stderr drain to relay server logs
                try:
                    if self.process and self.process.stderr:
                        # Ensure _ready_event exists
                        if self._ready_event is None:
                            self._ready_event = asyncio.Event()
                        self._stderr_task = asyncio.create_task(self._drain_stderr())
                except Exception as _e:
                    self.logger.debug(f"Failed to start stderr drain task: {_e!r}")

                # Wait for readiness marker; do NOT auto-initialize here to avoid race
                try:
                    # If process already died, surface stderr
                    if self.process and (self.process.poll() is not None):
                        try:
                            err_out = self.process.stderr.read().decode("utf-8", errors="ignore") if self.process.stderr else ""
                        except Exception:
                            err_out = ""
                        raise RuntimeError(f"MCP server exited early with code {self.process.poll()}. Stderr: {err_out[:500]}")
                    if self._ready_event:
                        await asyncio.wait_for(self._ready_event.wait(), timeout=20.0)
                except Exception:
                    # proceed even if not ready; callers will wait before sending requests
                    pass

        except Exception as e:
            self.logger.error(f"Failed to start MCP server process: {e}")
            raise

    async def stop(self):
        """Stop the MCP server process"""
        if self.process:
            try:
                # Close stdin to signal EOF to the child
                try:
                    if self.process.stdin and not self.process.stdin.closed:
                        self.process.stdin.close()
                except Exception:
                    pass

                # Try graceful terminate with blocking wait in executor (Popen.wait is blocking)
                self.process.terminate()
                loop = asyncio.get_event_loop()
                try:
                    await asyncio.wait_for(loop.run_in_executor(None, self.process.wait), timeout=5.0)
                except (asyncio.TimeoutError, asyncio.CancelledError):
                    self.logger.warning("MCP server process didn't terminate gracefully, killing it")
                    self.process.kill()
                    try:
                        await asyncio.wait_for(loop.run_in_executor(None, self.process.wait), timeout=2.0)
                    except Exception:
                        pass
                self.logger.info("MCP server process stopped")
            except Exception as e:
                self.logger.error(f"Error stopping MCP server process: {e}")
            finally:
                # Cancel stderr drain task
                try:
                    if self._stderr_task and not self._stderr_task.done():
                        self._stderr_task.cancel()
                except Exception:
                    pass
                # Best-effort close of stdout/stderr
                try:
                    if self.process.stdout and not self.process.stdout.closed:
                        self.process.stdout.close()
                except Exception:
                    pass
                try:
                    if self.process.stderr and not self.process.stderr.closed:
                        self.process.stderr.close()
                except Exception:
                    pass
                self.process = None

    async def _drain_stderr(self):
        """Continuously read child's stderr and relay to logger (INFO level)."""
        try:
            if not self.process or not self.process.stderr:
                return
            loop = asyncio.get_event_loop()
            def _readline():
                assert self.process and self.process.stderr is not None
                return self.process.stderr.readline()
            while True:
                try:
                    line = await loop.run_in_executor(None, _readline)
                except Exception:
                    break
                if not line:
                    break
                try:
                    txt = line.decode("utf-8", errors="ignore") if isinstance(line, (bytes, bytearray)) else str(line)
                except Exception:
                    txt = str(line)
                if txt.strip():
                    self.logger.info(f"[server-stderr] {txt.rstrip()}" )
                    # Signal readiness ONLY when Telegram client is fully initialized
                    try:
                        if self._ready_event and ("Telegram client ready, tools registered." in txt):
                            self.logger.debug("MCP server is fully ready (Telegram client initialized)")
                            self._ready_event.set()
                    except Exception:
                        pass
        except asyncio.CancelledError:
            return
        except Exception as e:
            self.logger.debug(f"stderr drain error: {e!r}")

    async def call_tool(self, tool_name: str, args: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Call a tool using appropriate transport"""
        if self.transport == "http":
            return await self._call_tool_http(tool_name, args)
        elif self.transport == "stdio":
            return await self._call_tool_stdio(tool_name, args)
        else:
            raise ValueError(f"Unsupported transport: {self.transport}")

    async def _call_tool_stdio(self, tool_name: str, args: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Call a tool via stdio MCP server using JSON-RPC tools/call."""
        if not self.process:
            await self.start()
        # Ensure server readiness and initialize once
        await self._wait_ready(timeout=20.0)
        if not self._initialized:
            try:
                await self.initialize()
            except Exception:
                # Continue best-effort
                pass
        request = {
            "jsonrpc": "2.0",
            "id": self.request_id,
            "method": "tools/call",
            "params": {
                "name": tool_name,
                "arguments": args or {}
            }
        }
        self.request_id += 1
        # Use a slightly larger timeout to allow network I/O against Telegram
        result = await self._send_and_read(request, timeout_sec=30.0)
        return result

    async def initialize(self) -> Optional[Dict[str, Any]]:
        """Send MCP initialize request (stdio transport). Safe to call multiple times."""
        if self.transport != "stdio":
            return None
        if not self.process:
            await self.start()
        # Ensure readiness to avoid racing initialize before server is ready
        await self._wait_ready(timeout=20.0)
        # Use protocol version compatible with @modelcontextprotocol/sdk ^0.4.0
        request = {
            "jsonrpc": "2.0",
            "id": self.request_id,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-09-18",
                "clientInfo": {"name": "telegram_monitoring_agent", "version": "0.1.0"},
                "capabilities": {
                    "tools": {},
                    "resources": {},
                    "prompts": {}
                }
            }
        }
        self.logger.debug("Attempting initialize with protocolVersion=2024-09-18")
        self.request_id += 1
        last_result = await self._send_and_read(request, timeout_sec=10.0)
        if last_result is None:
            # Best-effort: mark initialized to allow follow-up calls (some servers auto-accept without explicit initialize)
            self.logger.warning("Initialize response not received; proceeding in best-effort mode.")
            self._initialized = True
        else:
            self._initialized = True
        return last_result

    async def list_tools(self) -> Optional[List[Dict[str, Any]]]:
        """List available tools from server (stdio transport)."""
        if self.transport != "stdio":
            return None
        if not self.process:
            await self.start()
        # Ensure server readiness before initialize/list
        await self._wait_ready(timeout=20.0)
        # Ensure initialize was attempted at least once
        if not self._initialized:
            try:
                await self.initialize()
            except Exception:
                pass
        request = {
            "jsonrpc": "2.0",
            "id": self.request_id,
            "method": "tools/list",
            "params": {}
        }
        self.request_id += 1
        result = await self._send_and_read(request, timeout_sec=10.0)
        if isinstance(result, dict) and "tools" in result:
            return result.get("tools")
        return None


    async def _call_tool_http(self, tool_name: str, args: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Call a tool using HTTP transport"""
        try:
            import aiohttp

            url = self.http_config.get("url", "http://localhost:3000")
            payload = {
                "tool": tool_name,
                "input": args
            }
            async with aiohttp.ClientSession() as session:
                async with session.post(f"{url}/tools", json=payload) as resp:
                    if resp.status == 200:
                        result = await resp.json()
                        # Unwrap MCP content payload if present: { content: [{ type: 'text', text: '...json...' }] }
                        try:
                            if isinstance(result, dict) and isinstance(result.get("content"), list) and result["content"]:
                                first = result["content"][0]
                                text = first.get("text") if isinstance(first, dict) else None
                                if isinstance(text, str):
                                    try:
                                        return json.loads(text)
                                    except json.JSONDecodeError:
                                        return {"text": text}
                        except Exception:
                            # Fall back to returning a raw result
                            pass
                        return result
                    else:
                        # Log non-200 with short body preview
                        try:
                            body = await resp.text()
                        except Exception:
                            body = ""
                        self.logger.error(f"HTTP request failed: status={resp.status}, body={body[:300]}")
                        # If a result contains an error about unknown tool, try aliases
                        if isinstance(result, dict) and result.get("error") in ("Unknown tool", "Tool not found"):
                            for alt in self._alternate_tool_names(tool_name):
                                payload_alt = {"tool": alt, "input": args}
                                async with session.post(f"{url}/tools", json=payload_alt) as resp2:
                                    if resp2.status == 200:
                                        r2 = await resp2.json()
                                        try:
                                            if isinstance(r2, dict) and isinstance(r2.get("content"), list) and r2["content"]:
                                                first = r2["content"][0]
                                                text = first.get("text") if isinstance(first, dict) else None
                                                if isinstance(text, str):
                                                    try:
                                                        return json.loads(text)
                                                    except json.JSONDecodeError:
                                                        return {"text": text}
                                        except Exception:
                                            pass
                                        return r2
                                    # non-200, try next alias
                        return result
        except Exception as e:
            self.logger.error(f"Error calling tool {tool_name} via HTTP: {e}")
            return None

    def _alternate_tool_names(self, name: str) -> List[str]:
        """Generate likely alternate names for a tool (dotted vs underscored, and known pairs)."""
        alts: List[str] = []
        # dot <-> underscore variants
        if "." in name:
            alts.append(name.replace(".", "_"))
        if "_" in name:
            alts.append(name.replace("_", "."))
        # known pairs
        if name == "tg.fetch_history":
            alts.append("tg.read_messages")
        elif name == "tg.read_messages":
            alts.append("tg.fetch_history")
        # Some older servers used tg_send_message, tg_get_updates, etc.
        legacy_map = {
            "tg.send_message": ["tg_send_message"],
            "tg.forward_message": ["tg_forward_message"],
            "tg.get_chats": ["tg_get_chats"],
            "tg.get_unread_count": ["tg_get_unread_count"],
            "tg.resolve_chat": ["tg_resolve_chat"],
        }
        alts.extend(legacy_map.get(name, []))
        # de-dup while preserving order
        seen = set([name])
        uniq = []
        for a in alts:
            if a not in seen:
                seen.add(a)
                uniq.append(a)
        return uniq


    async def _send_and_read(self, request: Dict[str, Any], timeout_sec: float) -> Optional[Dict[str, Any]]:
        """Send a JSON-RPC request over stdio using Content-Length framing and read a single response.

        The MCP SDK server (StdioServerTransport) uses LSP-like framing with headers:
        Content-Length: <N>\r\n\r\n<body>
        """
        if not self.process:
            return None
        try:
            # Serialize all writes/reads to avoid interleaved frames
            async with self._io_lock:
                # If the child process already exited, abort early with diagnostics
                if self.process and (self.process.poll() is not None):
                    try:
                        err_out = self.process.stderr.read().decode("utf-8", errors="ignore") if self.process.stderr else ""
                    except Exception:
                        err_out = ""
                    self.logger.error(f"MCP server already exited with code {self.process.poll()}. Stderr: {err_out[:500]}")
                    return None

            # Encode body and build headers (Content-Length only per LSP framing)
            body = (json.dumps(request)).encode("utf-8")
            headers = (f"Content-Length: {len(body)}\r\n\r\n").encode("ascii")
            self.logger.debug(f"Sending request (len={len(body)}): {request}")
            self.logger.debug(f"Raw message being sent: {repr(headers + body)}")
            try:
                assert self.process.stdin is not None
                combined = headers + body
                self.process.stdin.write(combined)
                self.process.stdin.flush()
                self.logger.debug("Message sent successfully, waiting for response...")
            except OSError as e:
                self.logger.error(f"Failed to write to MCP stdin: {e}")
                return None

            # Helpers to read until delimiter and then fixed-size body with a single overall deadline
            async def _read_until(delim: bytes, deadline: float) -> Optional[bytes]:
                loop = asyncio.get_event_loop()
                # Start with any leftover bytes from previous call
                buf = bytearray(self._rx_buffer)
                self._rx_buffer.clear()
                while True:
                    remaining = max(0.0, deadline - loop.time())
                    if remaining == 0.0:
                        # timeout: return what we have for diagnostics
                        self.logger.debug(f"Header read timeout with partial buffer length={len(buf)}")
                        return bytes(buf) if buf else None
                    def _read_some(sz: int = 64):
                        assert self.process and self.process.stdout is not None
                        return self.process.stdout.read(sz)
                    try:
                        chunk = await asyncio.wait_for(loop.run_in_executor(None, _read_some), timeout=remaining)
                    except asyncio.TimeoutError:
                        self.logger.debug("Header read inner timeout while waiting for bytes")
                        return bytes(buf) if buf else None
                    if not chunk:
                        break
                    buf += chunk
                    bbuf = bytes(buf)
                    # Break only when CRLFCRLF delimiter appears (LSP framing)
                    if delim in bbuf:
                        break
                return bytes(buf)

            async def _read_n(n: int, deadline: float) -> Optional[bytes]:
                loop = asyncio.get_event_loop()
                remaining_bytes = n
                chunks: list[bytes] = []
                while remaining_bytes > 0:
                    remaining_time = max(0.0, deadline - loop.time())
                    if remaining_time == 0.0:
                        return None
                    to_read = remaining_bytes
                    def _read_size(k: int):
                        assert self.process and self.process.stdout is not None
                        return self.process.stdout.read(k)
                    try:
                        chunk = await asyncio.wait_for(loop.run_in_executor(None, _read_size, to_read), timeout=remaining_time)
                    except asyncio.TimeoutError:
                        return None
                    if not chunk:
                        break
                    chunks.append(chunk)
                    remaining_bytes -= len(chunk)
                return b"".join(chunks)

            # Read headers with overall deadline, honoring any bytes already present in the buffer
            loop = asyncio.get_event_loop()
            deadline = loop.time() + max(0.1, float(timeout_sec if timeout_sec else 60.0))
            self.logger.debug(f"Waiting for headers with timeout {timeout_sec}s...")
            raw_headers = await _read_until(b"\r\n\r\n", deadline)
            if not raw_headers:
                # timeout or empty
                try:
                    err_out = self.process.stderr.read().decode("utf-8", errors="ignore") if self.process and self.process.stderr else ""
                except Exception:
                    err_out = ""
                self.logger.error(f"No headers received from MCP server (timeout after {timeout_sec}s). Stderr: {err_out[:500]}")
                return None
            self.logger.debug(f"Received headers: {repr(raw_headers)}")
            try:
                # Split headers and any leftover body bytes
                rh = bytes(raw_headers)
                sep = b"\r\n\r\n"
                sep_idx = rh.find(sep)
                used_sep = sep
                if sep_idx < 0:
                    self.logger.error(f"Could not find header/body delimiter in: {rh!r}")
                    return None
                header_bytes = rh[:sep_idx]
                leftover_body = rh[sep_idx + len(used_sep):]
                if leftover_body:
                    self.logger.debug(f"Leftover body bytes present after headers: {len(leftover_body)} bytes")
                headers_text = header_bytes.decode("ascii", errors="ignore")
                content_length = 0
                # split by either CRLF or LF
                lines = headers_text.split("\r\n") if "\r\n" in headers_text else headers_text.split("\n")
                for line in lines:
                    if line.strip().lower().startswith("content-length:"):
                        try:
                            content_length = int(line.split(":", 1)[1].strip())
                        except Exception:
                            content_length = 0
                        break
                if content_length <= 0:
                    self.logger.error(f"Invalid Content-Length in headers: {headers_text!r}")
                    return None
            except Exception as e:
                self.logger.error(f"Failed to parse headers: {e}")
                return None

            # Read body with same overall deadline
            # If we already have some of the body in leftover_body, consume it first
            extra_after_body: bytes = b""
            if 'leftover_body' in locals() and leftover_body:
                have = bytes(leftover_body)
                if len(have) >= content_length:
                    body_bytes = have[:content_length]
                    extra_after_body = have[content_length:]
                else:
                    need = content_length - len(have)
                    tail = await _read_n(need, deadline)
                    body_bytes = have + (tail or b"")
            else:
                body_bytes = await _read_n(content_length, deadline)
            if not body_bytes or len(body_bytes) < content_length:
                try:
                    err_out = self.process.stderr.read().decode("utf-8", errors="ignore") if self.process and self.process.stderr else ""
                except Exception:
                    err_out = ""
                self.logger.error(f"Incomplete body from MCP server. Received={len(body_bytes) if body_bytes else 0}/{content_length}. Stderr: {err_out[:500]}")
                return None

            # Preserve any extra bytes beyond the declared Content-Length for the next call
            if extra_after_body:
                self._rx_buffer.extend(extra_after_body)

            try:
                response_text = body_bytes.decode("utf-8")
                self.logger.debug(f"Raw response body: {repr(response_text)}")
                response = json.loads(response_text)
            except json.JSONDecodeError as e:
                self.logger.error(f"Failed to parse JSON response: {e}")
                return None

            self.logger.debug(f"Parsed response: {response}")
            if isinstance(response, dict) and "error" in response:
                self.logger.error(f"MCP server error: {response['error']}")
                return None

            result = response.get("result") if isinstance(response, dict) else None
            # Unwrap MCP content payload if present
            try:
                if isinstance(result, dict) and isinstance(result.get("content"), list) and result["content"]:
                    first = result["content"][0]
                    text = first.get("text") if isinstance(first, dict) else None
                    if isinstance(text, str):
                        try:
                            return json.loads(text)
                        except json.JSONDecodeError:
                            return {"text": text}
            except Exception:
                pass
            return result
        except Exception as e:
            self.logger.error(f"Error during stdio exchange: {e!r}")
            return None

    async def resolve_chat(self, input_chat: str) -> Optional[Dict[str, Any]]:
        """Resolve chat identifier using tg.resolve_chat tool"""
        normalized = self._normalize_chat(input_chat)
        return await self.call_tool("tg.resolve_chat", {"input": normalized})

    async def fetch_history(self, chat_id: str, **kwargs) -> Optional[Dict[str, Any]]:
        """Fetch message history using tg.fetch_history tool"""
        args = {"chat": self._normalize_chat(chat_id)}
        args.update(kwargs)
        return await self.call_tool("tg.fetch_history", args)

    async def send_message(self, chat_id: str, message: str) -> Optional[Dict[str, Any]]:
        """Send message using tg.send_message tool"""
        chat = self._normalize_chat(chat_id)
        return await self.call_tool("tg.send_message", {"chat": chat, "message": message})

    async def forward_message(self, from_chat: str, to_chat: str, message_id: int) -> Optional[Dict[str, Any]]:
        """Forward message using tg.forward_message tool"""
        _from = self._normalize_chat(from_chat)
        _to = self._normalize_chat(to_chat)
        return await self.call_tool("tg.forward_message", {
            "from_chat": _from,
            "to_chat": _to,
            "message_id": message_id
        })

    async def get_chats(self, **kwargs) -> Optional[Dict[str, Any]]:
        """Get list of chats using tg.get_chats tool"""
        return await self.call_tool("tg.get_chats", kwargs)

    async def read_messages(self, chat_id: str, **kwargs) -> Optional[Dict[str, Any]]:
        """Read messages using tg.read_messages tool"""
        args = {"chat": self._normalize_chat(chat_id)}
        args.update(kwargs)
        return await self.call_tool("tg.read_messages", args)

    async def get_unread_count(self, chat_id: str) -> Optional[Dict[str, Any]]:
        """Get server-side unread counters using tg.get_unread_count tool"""
        chat = self._normalize_chat(chat_id)
        return await self.call_tool("tg.get_unread_count", {"chat": chat})

    def _normalize_chat(self, value: Optional[str]) -> Optional[str]:
        """Normalize chat identifiers for MCP tools.

        - Strip leading '@' for usernames (e.g., '@channel' -> 'channel')
        - Leave numeric IDs and empty values as-is
        - Pass through t.me URLs unchanged
        """
        if value is None:
            return value
        s = str(value).strip()
        if not s:
            return s
        # t.me links or http(s) keep as-is
        if s.startswith("http://") or s.startswith("https://") or "/" in s:
            return s
        # numeric IDs keep as-is
        if s.lstrip("-").isdigit():
            return s
        # remove leading '@'
        if s.startswith('@'):
            return s[1:]
        return s
