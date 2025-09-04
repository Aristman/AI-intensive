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

    def _get_default_command(self) -> str:
        """Get the default command to run the Telegram MCP server"""
        # Path to mcp_servers/telegram_mcp_server/src/index.js relative to this file
        server_path = Path(__file__).parent.parent.parent / "mcp_servers" / "telegram_mcp_server" / "src" / "index.js"
        return f"node {server_path}"

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

    async def start(self):
        """Start the MCP server process"""
        try:
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
                    # Split command string into list for subprocess
                    import shlex
                    cmd = shlex.split(self.command)

                # Start the process
                self.process = subprocess.Popen(
                    cmd,
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    env=self.full_env,
                    text=True,
                    bufsize=1
                )

                self.logger.info("MCP server process started successfully")

                # Give the server time to initialize (npx may install on first run)
                await asyncio.sleep(2.0)

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
                except asyncio.TimeoutError:
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

    async def call_tool(self, tool_name: str, args: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Call a tool using appropriate transport"""
        if self.transport == "http":
            return await self._call_tool_http(tool_name, args)
        elif self.transport == "stdio":
            return await self._call_tool_stdio(tool_name, args)
        else:
            raise ValueError(f"Unsupported transport: {self.transport}")

    async def _call_tool_stdio(self, tool_name: str, args: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Call a tool using JSON-RPC over STDIO"""
        if not self.process:
            raise RuntimeError("MCP server process not started. Use 'async with' or call start() first.")

        # Create JSON-RPC request
        request = {
            "jsonrpc": "2.0",
            "id": self.request_id,
            "method": "tools/call",
            "params": {
                "name": tool_name,
                "arguments": args
            }
        }

        self.request_id += 1

        try:
            # Send request to stdin
            request_json = json.dumps(request) + "\n"
            self.logger.debug(f"Sending request: {request_json.strip()}")

            try:
                self.process.stdin.write(request_json)
                self.process.stdin.flush()
            except OSError as e:
                self.logger.error(f"Failed to write to MCP stdin: {e}")
                return None

            # Read response from stdout with timeout
            async def _readline():
                loop = asyncio.get_event_loop()
                return await loop.run_in_executor(None, self.process.stdout.readline)

            # Loop until we get a valid JSON line or timeout
            loop = asyncio.get_event_loop()
            deadline = loop.time() + 15.0
            while True:
                timeout = max(0.0, deadline - loop.time())
                if timeout == 0.0:
                    # If timeout, try to capture stderr for diagnostics
                    try:
                        err = None
                        if self.process and self.process.stderr:
                            err = await asyncio.get_event_loop().run_in_executor(None, self.process.stderr.read)
                        self.logger.error(f"Timeout waiting for MCP response. Stderr: {err[:500] if err else 'N/A'}")
                    except Exception:
                        pass
                    return None
                try:
                    response_line = await asyncio.wait_for(_readline(), timeout=timeout)
                except asyncio.TimeoutError:
                    continue

                if not response_line:
                    # If process exited, include return code and stderr
                    rc = self.process.poll()
                    if rc is not None:
                        try:
                            err_out = self.process.stderr.read() if self.process.stderr else ''
                        except Exception:
                            err_out = ''
                        self.logger.error(f"MCP server exited with code {rc}. Stderr: {err_out[:500]}")
                    else:
                        self.logger.error("No response received from MCP server")
                    return None

                line = response_line.strip()
                try:
                    response = json.loads(line)
                except json.JSONDecodeError:
                    # Log and keep reading (some tools may print banners/prompts)
                    self.logger.debug(f"Non-JSON stdout: {line[:200]}")
                    continue

                self.logger.debug(f"Received response: {response}")
                if "error" in response:
                    self.logger.error(f"MCP server error: {response['error']}")
                    return None
                return response.get("result")

        except json.JSONDecodeError as e:
            self.logger.error(f"Failed to parse JSON response: {e}")
            return None
        except Exception as e:
            self.logger.error(f"Error calling tool {tool_name}: {e}")
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
                async with session.post(f"{url}/tools", json=payload) as response:
                    if response.status == 200:
                        return await response.json()
                    else:
                        self.logger.error(f"HTTP request failed: {response.status}")
                        return None

        except ImportError:
            self.logger.error("aiohttp not installed for HTTP transport")
            return None
        except Exception as e:
            self.logger.error(f"Error calling tool {tool_name} via HTTP: {e}")
            return None

    async def resolve_chat(self, input_chat: str) -> Optional[Dict[str, Any]]:
        """Resolve chat identifier using tg.resolve_chat tool"""
        normalized = self._normalize_chat(input_chat)
        return await self.call_tool("tg.resolve_chat", {"input": normalized})

    async def fetch_history(self, chat_id: str, **kwargs) -> Optional[Dict[str, Any]]:
        """Fetch message history using tg.fetch_history tool"""
        args = {"chat": chat_id}
        args.update(kwargs)
        return await self.call_tool("tg.fetch_history", args)

    async def send_message(self, chat_id: str, message: str) -> Optional[Dict[str, Any]]:
        """Send message using tg.send_message tool"""
        chat = self._normalize_chat(chat_id)
        return await self.call_tool("tg.send_message", {
            "chat": chat,
            "message": message
        })

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
