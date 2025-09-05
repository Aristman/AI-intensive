import json
from typing import Any, Dict, List, Optional
from telethon import TelegramClient


class ToolsHandler:
    def __init__(self, client: TelegramClient):
        self.client = client
        self._tools_list = [
            {
                "name": "tg.resolve_chat",
                "description": "Alias of resolve_chat (compatibility)",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "input": {"type": ["string", "number"], "description": "Chat identifier (ID, username, or phone)"},
                        "chat": {"type": ["string", "number"], "description": "Chat identifier (alternative key)"},
                        "chatId": {"type": ["string", "number"], "description": "Chat identifier (alternative key)"}
                    },
                    "required": []
                }
            },
            {
                "name": "tg.fetch_history",
                "description": "Alias of get_chat_history (compatibility)",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "chat": {"type": ["string", "number"], "description": "Chat identifier"},
                        "page_size": {"type": "number", "description": "Page size", "default": 50},
                        "min_id": {"type": "number", "description": "Fetch messages with id > min_id"},
                        "max_id": {"type": "number", "description": "Fetch messages with id <= max_id"}
                    },
                    "required": ["chat"]
                }
            },
            {
                "name": "tg.send_message",
                "description": "Alias of send_message (compatibility)",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "chat": {"type": ["string", "number"], "description": "Chat identifier"},
                        "message": {"type": "string", "description": "Message text"}
                    },
                    "required": ["chat", "message"]
                }
            },
            {
                "name": "tg.forward_message",
                "description": "Alias of forward_message (compatibility)",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "from_chat": {"type": ["string", "number"], "description": "Source chat identifier"},
                        "message_id": {"type": "number", "description": "Message ID to forward"},
                        "to_chat": {"type": ["string", "number"], "description": "Destination chat identifier"}
                    },
                    "required": ["from_chat", "message_id", "to_chat"]
                }
            },
            {
                "name": "tg.mark_read",
                "description": "Mark messages as read in a chat.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "chat": {"type": ["string", "number"], "description": "Chat identifier"},
                        "message_ids": {"type": "array", "items": {"type": "number"}, "description": "Array of message IDs to mark as read"},
                        "messageIds": {"type": "array", "items": {"type": "number"}, "description": "Alternative camelCase key"}
                    },
                    "required": ["chat", "message_ids"]
                }
            },
            {
                "name": "tg.get_unread_count",
                "description": "Get the total number of unread messages.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "chat": {"type": ["string", "number"], "description": "Optional: specific chat to query"}
                    },
                    "required": []
                }
            },
            {
                "name": "tg.get_chats",
                "description": "List available chats and basic metadata.",
                "inputSchema": {"type": "object", "properties": {}, "required": []}
            },
            {
                "name": "tg.read_messages",
                "description": "Read messages from a chat (equivalent to fetch_history).",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "chat": {"type": ["string", "number"], "description": "Chat identifier"},
                        "page_size": {"type": "number", "description": "Page size", "default": 50},
                        "min_id": {"type": "number", "description": "Fetch messages with id > min_id"},
                        "max_id": {"type": "number", "description": "Fetch messages with id <= max_id"}
                    },
                    "required": ["chat"]
                }
            }
        ]

    async def list(self) -> List[Dict[str, Any]]:
        return self._tools_list

    async def call(self, name: str, params: Optional[Dict[str, Any]]) -> Any:
        params = params or {}
        try:
            chat_arg = params.get("chat") if params.get("chat") is not None else params.get("chatId", params.get("input"))
            page_size = params.get("page_size", params.get("limit"))
            min_id = params.get("min_id", params.get("minId"))
            max_id = params.get("max_id", params.get("maxId"))

            if name == "tg.resolve_chat":
                entity = await self.client.get_entity(chat_arg)
                _id = getattr(entity, "id", None)
                peer = getattr(entity, "peer_id", None)
                if _id is None and peer is not None:
                    _id = getattr(peer, "channel_id", None) or getattr(peer, "chat_id", None) or getattr(peer, "user_id", None)
                username = getattr(entity, "username", None) or getattr(getattr(entity, "user", None), "username", None)
                title = getattr(entity, "title", None)
                if not title:
                    first = getattr(entity, "first_name", None) or getattr(entity, "firstName", None)
                    last = getattr(entity, "last_name", None) or getattr(entity, "lastName", None)
                    parts = [p for p in [first, last] if p]
                    title = (" ".join(parts)) or username or (str(_id) if _id is not None else None)
                type_name = getattr(entity, "__class__", type(entity)).__name__
                return {"id": _id, "username": username, "title": title, "type": type_name}

            elif name in ("tg.read_messages", "tg.fetch_history"):
                limit = page_size or 50
                opts: Dict[str, Any] = {"limit": int(limit)}
                if isinstance(min_id, int):
                    opts["min_id"] = min_id
                if isinstance(max_id, int):
                    opts["max_id"] = max_id
                if isinstance(params.get("offset"), int):
                    opts["add_offset"] = params.get("offset")
                raw = await self.client.get_messages(chat_arg, **opts)
                out = []
                for m in raw or []:
                    sender = getattr(m, "sender", None)
                    display = None
                    if sender is not None:
                        username = getattr(sender, "username", None)
                        if username:
                            display = username
                        else:
                            first = getattr(sender, "first_name", None)
                            last = getattr(sender, "last_name", None)
                            parts = [p for p in [first, last] if p]
                            display = " ".join(parts) if parts else None
                    out.append({
                        "id": getattr(m, "id", None),
                        "text": getattr(m, "message", None) or getattr(m, "text", None) or "",
                        "date": getattr(m, "date", None),
                        "from": {
                            "id": getattr(m, "sender_id", None),
                            "display": display or (str(getattr(m, "sender_id", "Unknown")))
                        }
                    })
                return {"messages": out}

            elif name == "tg.send_message":
                text = params.get("text") or params.get("message")
                res = await self.client.send_message(chat_arg, message=text)
                return {"message_id": getattr(res, "id", None)}

            elif name == "tg.forward_message":
                from_chat = params.get("from_chat") or params.get("fromChatId")
                to_chat = params.get("to_chat") or params.get("toChatId")
                message_id = params.get("message_id") or params.get("messageId")
                res = await self.client.forward_messages(to_chat, [int(message_id)], from_peer=from_chat)
                first = res[0] if isinstance(res, list) and res else res
                return {"forwarded_id": getattr(first, "id", None)}

            elif name == "tg.mark_read":
                ids = params.get("message_ids") or params.get("messageIds") or []
                await self.client.send_read_acknowledge(chat_arg, max_id=max(ids) if ids else None, message_ids=ids or None)
                return {"success": True}

            elif name == "tg.get_unread_count":
                dialogs = await self.client.get_dialogs()
                unread = 0
                if chat_arg:
                    for d in dialogs:
                        if getattr(d, "id", None) == chat_arg or getattr(getattr(d, "entity", None), "username", None) == chat_arg:
                            unread += getattr(d, "unread_count", 0)
                else:
                    for d in dialogs:
                        uc = getattr(d, "unread_count", 0)
                        if uc:
                            unread += uc
                return {"unread": unread}

            elif name == "tg.get_chats":
                dialogs = await self.client.get_dialogs()
                mapped = []
                for d in dialogs:
                    mapped.append({
                        "id": getattr(d, "id", None),
                        "title": getattr(d, "title", None),
                        "username": getattr(getattr(d, "entity", None), "username", None),
                        "unread": getattr(d, "unread_count", 0)
                    })
                return mapped

            else:
                return {"error": "Unknown tool"}
        except Exception as e:
            return {"error": str(e)}
