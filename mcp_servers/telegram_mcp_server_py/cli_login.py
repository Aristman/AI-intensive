#!/usr/bin/env python3
"""
Interactive CLI utility to create/update Telegram session for the Python MCP server.
Usage examples:
  # Bot login (recommended for MCP)
  python -m mcp_servers.telegram_mcp_server_py.cli_login --bot-token <TOKEN> [--session-file path]

  # User login (will require SMS/Telegram code, and optionally 2FA password)
  python -m mcp_servers.telegram_mcp_server_py.cli_login --api-id <ID> --api-hash <HASH> --phone <PHONE> [--session-file path]

If arguments are omitted, the tool will try to read from .env placed next to this module
(mcp_servers/telegram_mcp_server_py/.env): TELEGRAM_API_ID, TELEGRAM_API_HASH,
TELEGRAM_PHONE_NUMBER, TELEGRAM_BOT_TOKEN, TELEGRAM_SESSION_FILE.
"""

import sys
import argparse
from pathlib import Path
from getpass import getpass
from dotenv import load_dotenv
import os
from telethon import TelegramClient
from telethon.sessions import StringSession


def main() -> int:
    # Load .env if present
    env_path = Path(__file__).parent / ".env"
    if env_path.exists():
        load_dotenv(dotenv_path=env_path)

    parser = argparse.ArgumentParser(description="Telegram session login for MCP server")
    parser.add_argument("--bot-token", dest="bot_token", default=os.getenv("TELEGRAM_BOT_TOKEN"))
    parser.add_argument("--api-id", dest="api_id", default=os.getenv("TELEGRAM_API_ID"))
    parser.add_argument("--api-hash", dest="api_hash", default=os.getenv("TELEGRAM_API_HASH"))
    parser.add_argument("--phone", dest="phone", default=os.getenv("TELEGRAM_PHONE_NUMBER"))
    parser.add_argument("--session-file", dest="session_file", default=os.getenv("TELEGRAM_SESSION_FILE"))

    args = parser.parse_args()

    # Default session file near this module
    session_file = args.session_file or str(Path(__file__).parent / "session.txt")

    # Load existing session (if any)
    session_str = ""
    try:
        p = Path(session_file)
        if p.exists():
            session_str = p.read_text(encoding="utf-8").strip()
    except Exception as e:
        print(f"Warning: failed to read existing session: {e}")

    if args.bot_token:
        # Bot auth path
        api_id = int(args.api_id or 0)
        api_hash = args.api_hash or ""
        client = TelegramClient(StringSession(session_str), api_id, api_hash,
                                device_model="Telegram MCP Server", system_version="1.0", app_version="0.1.0")
        print("Logging in as bot...")
        try:
            client.start(bot_token=args.bot_token)
            # Persist session
            _persist_session(client, session_file)
            print("Bot login successful. Session saved to:", session_file)
            return 0
        except Exception as e:
            print("Bot login failed:", e)
            return 1

    # User auth path
    if not args.api_id or not args.api_hash or not args.phone:
        print("Missing credentials. Provide either --bot-token or user creds: --api-id --api-hash --phone")
        return 2

    api_id = int(args.api_id)
    api_hash = args.api_hash
    phone = args.phone

    client = TelegramClient(StringSession(session_str), api_id, api_hash,
                            device_model="Telegram MCP Server", system_version="1.0", app_version="0.1.0")
    print("Logging in as user (you may need to enter a code and possibly 2FA password)...")

    def _code_callback():
        return input("Enter the code you received: ")

    def _password_callback(hint: str = ""):
        return getpass("Enter your 2FA password (if enabled): ")

    try:
        client.start(phone=phone, code_callback=_code_callback, password=_password_callback)
        _persist_session(client, session_file)
        print("User login successful. Session saved to:", session_file)
        return 0
    except Exception as e:
        print("User login failed:", e)
        return 1


def _persist_session(client: TelegramClient, session_file: str) -> None:
    try:
        s = client.session.save()
        Path(session_file).write_text(s, encoding="utf-8")
    except Exception as e:
        print(f"Failed to save session: {e}")


if __name__ == "__main__":
    sys.exit(main())
