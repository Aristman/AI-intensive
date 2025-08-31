#!/usr/bin/env python3
"""
Background monitoring runner for TelegramAgent.
Usage:
  - Ensure config at telegram_monitoring_agent/config/config.json
  - Run from repo root:
      python tools/run_monitor.py
    or after moving tools under telegram_monitoring_agent:
      python telegram_monitoring_agent/tools/run_monitor.py
"""
import asyncio
import signal
import sys
import logging
import os

# Ensure repository root is on sys.path regardless of CWD and script location.
_THIS_DIR = os.path.abspath(os.path.dirname(__file__))

def _find_repo_root(start_dir: str) -> str:
    """Walk up from start_dir to locate repo root containing 'telegram_monitoring_agent' package or .git."""
    cur = start_dir
    for _ in range(5):
        if os.path.isdir(os.path.join(cur, 'telegram_monitoring_agent')) or os.path.isdir(os.path.join(cur, '.git')):
            return cur
        parent = os.path.abspath(os.path.join(cur, os.pardir))
        if parent == cur:
            break
        cur = parent
    return start_dir

_REPO_ROOT = _find_repo_root(_THIS_DIR)
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

from telegram_monitoring_agent.src.agent import TelegramAgent

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("MonitorRunner")


async def main():
    # Use absolute config path to avoid path-related issues
    config_path = os.path.join(_REPO_ROOT, 'telegram_monitoring_agent', 'config', 'config.json')
    logger.info(f"Using config: {config_path}")
    agent = TelegramAgent(config_path=config_path)

    stop_event = asyncio.Event()

    def _graceful_shutdown(*_):
        logger.info("Shutdown signal received, stopping monitor loop...")
        stop_event.set()

    loop = asyncio.get_event_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _graceful_shutdown)
        except NotImplementedError:
            # Windows may not support signal handlers in asyncio
            pass

    logger.info("Starting continuous monitoring...")

    monitor_task = asyncio.create_task(agent.start_continuous_monitoring())

    try:
        await stop_event.wait()
    finally:
        monitor_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await monitor_task
        logger.info("Monitor stopped.")


if __name__ == "__main__":
    try:
        import contextlib  # delayed import to keep top tidy
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
