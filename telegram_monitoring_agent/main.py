#!/usr/bin/env python3
"""
Telegram Monitoring Agent - Main Entry Point
"""

from src.agent import TelegramAgent

def main():
    agent = TelegramAgent()
    agent.run()

if __name__ == "__main__":
    main()
