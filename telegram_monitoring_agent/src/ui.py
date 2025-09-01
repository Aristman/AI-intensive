#!/usr/bin/env python3
"""
Telegram Monitoring Agent UI
"""

import tkinter as tk
from tkinter import ttk, scrolledtext
import asyncio
import threading

class TelegramUI:
    def __init__(self, agent=None):
        self.agent = agent
        self.root = tk.Tk()
        self.root.title("Telegram Monitoring Agent")
        self.root.geometry("800x600")

        self.setup_ui()

    def setup_ui(self):
        # App bar
        self.appbar = tk.Frame(self.root, bg="#f0f0f0", height=50)
        self.appbar.pack(fill=tk.X, side=tk.TOP)

        self.title_label = tk.Label(self.appbar, text="Telegram Monitoring Agent",
                                   font=("Arial", 14, "bold"), bg="#f0f0f0")
        self.title_label.pack(side=tk.LEFT, padx=20, pady=10)

        self.model_label = tk.Label(self.appbar, text="LLM: Connected",
                                   bg="#f0f0f0")
        self.model_label.pack(side=tk.LEFT, padx=20)

        # MCP status indicator
        self.mcp_status_label = tk.Label(self.appbar, text="MCP: неизвестно",
                                         bg="#f0f0f0")
        self.mcp_status_label.pack(side=tk.LEFT, padx=10)

        # Check MCP button
        self.check_mcp_btn = tk.Button(self.appbar, text="Проверить MCP",
                                       command=self.check_mcp)
        self.check_mcp_btn.pack(side=tk.LEFT, padx=10)

        self.clear_btn = tk.Button(self.appbar, text="Очистить контекст",
                                  command=self.clear_context)
        self.clear_btn.pack(side=tk.RIGHT, padx=10)

        self.settings_btn = tk.Button(self.appbar, text="Настройки",
                                     command=self.open_settings)
        self.settings_btn.pack(side=tk.RIGHT, padx=10)

        # Main chat area
        self.chat_frame = tk.Frame(self.root)
        self.chat_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        self.chat_area = scrolledtext.ScrolledText(self.chat_frame,
                                                 wrap=tk.WORD,
                                                 state=tk.DISABLED)
        self.chat_area.pack(fill=tk.BOTH, expand=True)

        # Input area
        self.input_frame = tk.Frame(self.root, height=60)
        self.input_frame.pack(fill=tk.X, side=tk.BOTTOM, padx=10, pady=10)

        self.input_field = tk.Entry(self.input_frame, font=("Arial", 12))
        self.input_field.pack(side=tk.LEFT, fill=tk.X, expand=True)
        self.input_field.bind("<Return>", self.send_message)

        self.send_btn = tk.Button(self.input_frame, text="Отправить",
                                 command=self.send_message)
        self.send_btn.pack(side=tk.RIGHT, padx=(10,0))

        # Initial MCP status check and periodic refresh
        self.set_mcp_status("unknown")
        self.root.after(200, self.check_mcp)  # initial delayed check
        self.root.after(60000, self._schedule_mcp_refresh)  # periodic

    def add_message(self, message: str, sender: str = "user"):
        """Add message to chat area"""
        self.chat_area.config(state=tk.NORMAL)

        if sender == "user":
            tag = "user"
            bg = "#e3f2fd"  # Light blue
        elif sender == "agent":
            tag = "agent"
            bg = "#e8f5e8"  # Light green
        else:
            tag = "system"
            bg = "#fff9c4"  # Light yellow

        self.chat_area.tag_config(tag, background=bg, lmargin1=10, lmargin2=10,
                                 rmargin=10, spacing1=5, spacing3=5)

        self.chat_area.insert(tk.END, f"{sender.title()}: {message}\n", tag)
        self.chat_area.see(tk.END)
        self.chat_area.config(state=tk.DISABLED)

    def send_message(self, event=None):
        """Send user message"""
        message = self.input_field.get().strip()
        if message:
            self.add_message(message, "user")
            self.input_field.delete(0, tk.END)

            # Process in background thread
            threading.Thread(target=self.process_message, args=(message,),
                           daemon=True).start()

    def process_message(self, message: str):
        """Process message asynchronously"""
        try:
            if not self.agent:
                self.root.after(0, lambda: self.add_message("Agent not initialized", "system"))
                return
                
            # Run async processing
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            response = loop.run_until_complete(self.agent.process_user_query(message))
            loop.close()

            self.root.after(0, lambda: self.add_message(response, "agent"))
        except Exception as e:
            self.root.after(0, lambda: self.add_message(f"Error: {str(e)}", "system"))

    def set_mcp_status(self, status: str):
        """Set MCP status label with color coding"""
        status = (status or "unknown").lower()
        mapping = {
            "healthy": ("MCP: подключено", "#e8f5e8"),
            "unhealthy": ("MCP: не подключено", "#ffebee"),
            "error": ("MCP: ошибка", "#ffebee"),
            "unknown": ("MCP: неизвестно", "#f0f0f0")
        }
        text, bg = mapping.get(status, mapping["unknown"])
        self.mcp_status_label.config(text=text, bg=bg)

    def _schedule_mcp_refresh(self):
        """Periodic MCP status refresh"""
        threading.Thread(target=self._check_mcp_background, daemon=True).start()
        self.root.after(60000, self._schedule_mcp_refresh)

    def check_mcp(self):
        """Trigger MCP status check in background"""
        threading.Thread(target=self._check_mcp_background, daemon=True).start()

    def _check_mcp_background(self):
        """Background worker to call agent.health_check asynchronously"""
        try:
            if not self.agent:
                self.root.after(0, lambda: self.set_mcp_status("unknown"))
                return
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            health = loop.run_until_complete(self.agent.health_check())
            loop.close()

            status = "unknown"
            checks = health.get("checks", {}) if isinstance(health, dict) else {}
            mcp_check = checks.get("mcp_connection")
            if isinstance(mcp_check, str):
                if mcp_check.startswith("error"):
                    status = "error"
                else:
                    status = mcp_check
            self.root.after(0, lambda: self.set_mcp_status(status))
        except Exception:
            self.root.after(0, lambda: self.set_mcp_status("error"))

    def clear_context(self):
        """Clear chat context"""
        self.chat_area.config(state=tk.NORMAL)
        self.chat_area.delete(1.0, tk.END)
        self.chat_area.config(state=tk.DISABLED)
        self.add_message("Контекст очищен", "system")

    def open_settings(self):
        """Open settings window"""
        # TODO: Implement settings dialog
        self.add_message("Настройки пока не реализованы", "system")

    def run(self):
        """Run the UI"""
        self.root.mainloop()
