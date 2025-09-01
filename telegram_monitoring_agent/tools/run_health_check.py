import asyncio
import json
import sys
from pathlib import Path

# Ensure repository root is on sys.path
REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

try:
    from telegram_monitoring_agent.src.agent import TelegramAgent
except ModuleNotFoundError as e:
    print(f"Import error: {e}\nPYTHONPATH={sys.path}")
    raise

CONFIG_PATH = 'telegram_monitoring_agent/config/config.json'

async def main():
    print("[health-check] initializing agent...")
    agent = TelegramAgent(CONFIG_PATH)
    print("[health-check] running health_check() with 30s timeout...")
    try:
        result = await asyncio.wait_for(agent.health_check(), timeout=30)
        print("[health-check] result:")
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except asyncio.TimeoutError:
        print("[health-check] ERROR: timeout waiting for health_check()")
    except Exception as e:
        print(f"[health-check] ERROR: {e}")

if __name__ == "__main__":
    asyncio.run(main())
