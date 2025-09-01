#!/usr/bin/env python3
"""
DeepSeek LLM Implementation using OpenAI client
"""

import os
from typing import List, Dict, Any
from openai import OpenAI
from .llm_usecase import LlmUseCase


class DeepSeekUseCase(LlmUseCase):
    """DeepSeek LLM implementation using OpenAI client"""

    def __init__(self):
        self.api_key = os.getenv('DEEPSEEK_API_KEY', '')
        self.client = OpenAI(
            api_key=self.api_key,
            base_url="https://api.deepseek.com/beta",
        )

    async def complete(self, messages: List[Dict[str, str]], **kwargs) -> str:
        """Complete the conversation using DeepSeek API via OpenAI client"""

        if not self.api_key:
            raise Exception("DeepSeek API key not found. Set DEEPSEEK_API_KEY environment variable")

        # Get parameters from kwargs or use defaults
        temperature = kwargs.get('temperature', 0.7)
        max_tokens = kwargs.get('max_tokens', 2000)

        # Convert messages to prompt format for completions API
        # Take the last user message as prompt
        user_messages = [msg for msg in messages if msg['role'] == 'user']
        system_messages = [msg for msg in messages if msg['role'] == 'system']

        if not user_messages:
            raise Exception("No user message found")

        # Create prompt from system + user messages
        prompt_parts = []
        if system_messages:
            prompt_parts.append(system_messages[-1]['content'])
        prompt_parts.append(user_messages[-1]['content'])

        prompt = '\n\n'.join(prompt_parts)

        try:
            response = self.client.completions.create(
                model="deepseek-chat",
                prompt=prompt,
                max_tokens=max_tokens,
                temperature=temperature,
            )

            if response.choices and len(response.choices) > 0:
                return response.choices[0].text.strip()
            else:
                raise Exception("Empty response from DeepSeek")

        except Exception as e:
            raise Exception(f"DeepSeek API error: {str(e)}")
