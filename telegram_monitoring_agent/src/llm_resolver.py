#!/usr/bin/env python3
"""
LLM Resolver - selects appropriate LLM implementation
"""

from .llm_usecase import LlmUseCase
from .deepseek_usecase import DeepSeekUseCase
from .yandexgpt_usecase import YandexGptUseCase


def resolve_llm_usecase(llm_provider: str = "deepseek") -> LlmUseCase:
    """Resolve LLM use case based on provider name"""
    if llm_provider.lower() == "deepseek":
        return DeepSeekUseCase()
    elif llm_provider.lower() == "yandexgpt":
        return YandexGptUseCase()
    else:
        # Default to DeepSeek
        return DeepSeekUseCase()
