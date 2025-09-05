import sys
import asyncio
from pathlib import Path
from typing import Optional
from telethon import TelegramClient
from telethon.sessions import StringSession
from telethon.errors import RPCError


async def setup_telegram_client(api_id: Optional[str], api_hash: Optional[str],
                                phone_number: Optional[str], bot_token: Optional[str],
                                session_file: Optional[str]) -> TelegramClient:
    """
    Initialize and authenticate Telegram client (bot or user). Save session to file.
    Logs are printed to stderr. Stdout must remain clean (reserved for MCP frames).
    """
    # Resolve session file path near this module by default
    if not session_file:
        session_file = str(Path(__file__).parent / "session.txt")

    # Read existing session
    session_str = ""
    try:
        p = Path(session_file)
        if p.exists():
            session_str = p.read_text(encoding="utf-8").strip()
    except Exception as e:
        print(f"Failed to read session file: {e}", file=sys.stderr)

    client = TelegramClient(StringSession(session_str), int(api_id or 0), api_hash or "",
                            device_model="Telegram MCP Server", system_version="1.0", app_version="0.1.0")
    try:
        if bot_token:
            print("Using bot authentication", file=sys.stderr)
            await client.start(bot_token=bot_token)
            await _persist_session(client, session_file)
            print("Bot client initialized successfully.", file=sys.stderr)
            return client
        else:
            # User flow: try non-interactive connect first
            if session_str:
                print("Using saved session (non-interactive connect)", file=sys.stderr)
                await client.connect()
                if await client.is_user_authorized():
                    print("User client initialized successfully.", file=sys.stderr)
                    return client
                if not sys.stdin.isatty():
                    raise RuntimeError("Interactive authorization required but no TTY available.")
            # Interactive flow requires TTY; we refuse in MCP daemon mode
            raise RuntimeError("Interactive authorization required. Run a separate login script to create session.txt.")
    except RPCError as e:
        print(f"Telegram RPC error: {e}", file=sys.stderr)
        raise
    except Exception as e:
        print(f"Failed to initialize Telegram client: {e}", file=sys.stderr)
        raise


async def _persist_session(client: TelegramClient, session_file: str) -> None:
    try:
        s = client.session.save()
        Path(session_file).write_text(s, encoding="utf-8")
        print(f"Session saved to {session_file}", file=sys.stderr)
    except Exception as e:
        print(f"Failed to save session: {e}", file=sys.stderr)
