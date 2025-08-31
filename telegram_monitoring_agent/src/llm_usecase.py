#!/usr/bin/env python3
"""
LLM Use Case Interface
"""

from abc import ABC, abstractmethod
from typing import List, Dict, Any


class LlmUseCase(ABC):
    """Abstract base class for LLM implementations"""

    @abstractmethod
    async def complete(self, messages: List[Dict[str, str]], **kwargs) -> str:
        """Complete the conversation with LLM"""
        pass
