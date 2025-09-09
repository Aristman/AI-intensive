from typing import Any, Dict, List


async def list_resources() -> List[Dict[str, Any]]:
    # Placeholder for future resources (e.g., chats as resources)
    return []


async def read_resource(uri: str) -> Dict[str, Any]:
    # Placeholder: return not found
    return {"contents": {"error": "Resource not found"}}
