import os
from pathlib import Path

# Attempt to import python-dotenv; proceed without it if unavailable
try:
    from dotenv import load_dotenv  # type: ignore
except Exception:  # pragma: no cover
    load_dotenv = None  # type: ignore

# Load .env placed alongside this package (mcp_servers/telegram_mcp_server_py/.env)
_ENV_PATH = Path(__file__).parent / ".env"
if _ENV_PATH.exists() and load_dotenv:
    load_dotenv(dotenv_path=_ENV_PATH)


class Config:
    name: str = "telegram-mcp-server"
    version: str = "0.1.0"

    telegram = {
        "api_id": os.getenv("TELEGRAM_API_ID"),
        "api_hash": os.getenv("TELEGRAM_API_HASH"),
        "phone_number": os.getenv("TELEGRAM_PHONE_NUMBER"),
        "bot_token": os.getenv("TELEGRAM_BOT_TOKEN"),
        "session_file": os.getenv("TELEGRAM_SESSION_FILE"),
    }


def validate_config() -> None:
    t = Config.telegram
    has_user = bool(t.get("api_id") and t.get("api_hash") and t.get("phone_number"))
    has_bot = bool(t.get("bot_token"))
    if not (has_user or has_bot):
        # Print to stderr, not stdout (stdout reserved for MCP frames)
        import sys
        print(
            "Missing required env. Provide user (TELEGRAM_API_ID, TELEGRAM_API_HASH, TELEGRAM_PHONE_NUMBER) "
            "or bot (TELEGRAM_BOT_TOKEN) credentials",
            file=sys.stderr,
        )
        # Do not exit here to allow tools/list to be empty; but server will not be fully ready
