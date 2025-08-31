#!/usr/bin/env python3
"""
YandexGPT LLM Implementation
"""

import aiohttp
import json
import os
from typing import List, Dict, Any
from .llm_usecase import LlmUseCase


class YandexGptUseCase(LlmUseCase):
    """YandexGPT LLM implementation"""

    def __init__(self):
        self.api_url = os.getenv('YANDEX_GPT_BASE_URL',
                                'https://llm.api.cloud.yandex.net/foundationModels/v1/completion')
        self.iam_token = os.getenv('YANDEX_IAM_TOKEN', '')
        self.api_key = os.getenv('YANDEX_API_KEY', '')
        self.folder_id = os.getenv('YANDEX_FOLDER_ID', '')
        self.model_uri = os.getenv('YANDEX_MODEL_URI', f'gpt://{self.folder_id}/yandexgpt')

    async def complete(self, messages: List[Dict[str, str]], **kwargs) -> str:
        """Complete the conversation using YandexGPT API"""

        # Check authentication
        if not self.iam_token and not self.api_key:
            raise Exception("YandexGPT authentication not found. Set YANDEX_IAM_TOKEN or YANDEX_API_KEY")

        if not self.folder_id:
            raise Exception("YandexGPT folder ID not found. Set YANDEX_FOLDER_ID")

        # Get parameters from kwargs or use defaults
        temperature = kwargs.get('temperature', 0.7)
        max_tokens = kwargs.get('max_tokens', 2000)

        # Convert messages to YandexGPT format
        yc_messages = []
        for msg in messages:
            yc_messages.append({
                'role': msg['role'],
                'text': msg['content']
            })

        request_body = {
            'modelUri': self.model_uri,
            'completionOptions': {
                'stream': False,
                'temperature': temperature,
                'maxTokens': max_tokens,
            },
            'messages': yc_messages,
        }

        headers = {'Content-Type': 'application/json'}

        if self.iam_token:
            headers['Authorization'] = f'Bearer {self.iam_token}'
        else:
            headers['Authorization'] = f'Api-Key {self.api_key}'
            headers['x-folder-id'] = self.folder_id

        async with aiohttp.ClientSession() as session:
            async with session.post(self.api_url, headers=headers, json=request_body) as response:
                if response.status != 200:
                    error_text = await response.text()
                    raise Exception(f"YandexGPT API error {response.status}: {error_text}")

                data = await response.json()
                text = data.get('result', {}).get('alternatives', [{}])[0].get('message', {}).get('text', '')

                if not text:
                    raise Exception("Empty response from YandexGPT")

                return text
