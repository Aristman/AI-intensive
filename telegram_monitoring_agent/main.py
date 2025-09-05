#!/usr/bin/env python3
"""
Telegram Monitoring Agent - Main Entry Point
"""

import asyncio
import argparse
from src.agent import TelegramAgent


def main():
    parser = argparse.ArgumentParser(description="Telegram Monitoring Agent")
    parser.add_argument("--test-mcp", action="store_true", help="Test MCP stdio connection and resolve a test chat (no messages will be sent)")
    parser.add_argument("--list-tools", action="store_true", help="List tools exposed by MCP server (stdio)")
    args = parser.parse_args()

    agent = TelegramAgent()

    if args.test_mcp:
        asyncio.run(agent.test_connection())
        return

    if args.list_tools:
        async def _list():
            async with agent.mcp_client:
                tools = await agent.mcp_client.list_tools()
                if tools:
                    print("Available MCP tools:")
                    for t in tools:
                        name = t.get("name") if isinstance(t, dict) else str(t)
                        print(f" - {name}")
                else:
                    print("No tools returned or failed to list tools.")
        asyncio.run(_list())
        return

    # Default behavior: start the agent main loop (as previously)
    agent.run()


if __name__ == "__main__":
    main()
