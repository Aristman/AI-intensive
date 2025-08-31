#!/usr/bin/env python3
"""
DeepSeek LLM Implementation
"""

import aiohttp
import json
import os
from typing import List, Dict, Any
from .llm_usecase import LlmUseCase


class DeepSeekUseCase(LlmUseCase):
    """DeepSeek LLM implementation"""

    def __init__(self):
        self.api_url = "https://api.deepseek.com/chat/completions"
        self.api_key = os.getenv('DEEPSEEK_API_KEY', '')

    async def complete(self, messages: List[Dict[str, str]], **kwargs) -> str:
        """Complete the conversation using DeepSeek API"""

        if not self.api_key:
            raise Exception("DeepSeek API key not found. Set DEEPSEEK_API_KEY environment variable")

        # Get parameters from kwargs or use defaults
        temperature = kwargs.get('temperature', 0.7)
        max_tokens = kwargs.get('max_tokens', 2000)
        model = kwargs.get('model', 'deepseek-chat')

        request_body = {
            'model': model,
            'messages': messages,
            'stream': False,
            'max_tokens': max_tokens,
            'temperature': temperature,
        }

        headers = {
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {self.api_key}',
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(self.api_url, headers=headers, json=request_body) as response:
                if response.status != 200:
                    error_text = await response.text()
                    raise Exception(f"DeepSeek API error {response.status}: {error_text}")

                data = await response.json()
                content = data.get('choices', [{}])[0].get('message', {}).get('content', '')

                if not content:
                    raise Exception("Empty response from DeepSeek")

                return content
