#!/usr/bin/env python3
"""
Tests for Telegram Monitoring Agent
"""

import unittest
from unittest.mock import Mock, patch
from src.agent import TelegramAgent
from src.mcp_client import MCPClient

class TestTelegramAgent(unittest.TestCase):
    def setUp(self):
        self.agent = TelegramAgent("config/config.json")

    def test_load_config(self):
        config = self.agent.load_config("config/config.json")
        self.assertIsInstance(config, dict)
        self.assertIn("llm_api_key", config)

    def test_default_config(self):
        config = self.agent.default_config()
        self.assertIsInstance(config, dict)
        self.assertIn("chats", config)

    @patch('src.agent.TelegramAgent.summarize_with_llm', return_value='Summary done')
    async def test_process_message(self, mock_summarize):
        message = {
            'text': 'Test message',
            'from': {'display': 'TestUser'}
        }
        await self.agent.process_message(message)
        
    def test_get_monitored_chats(self):
        chats = self.agent.get_monitored_chats()
        self.assertIsInstance(chats, list)
        self.assertIn('@telegram', chats)
        
    @patch('src.agent.MCPClient.resolve_chat')
    @patch('src.agent.MCPClient.fetch_history')
    async def test_monitor_chat(self, mock_fetch, mock_resolve):
        mock_resolve.return_value = {'chat_id': '123', 'title': 'Test Chat'}
        mock_fetch.return_value = {'messages': []}
        
        await self.agent.monitor_chat('@test')
        mock_resolve.assert_called_once_with('@test')
        mock_fetch.assert_called_once()
        
    @patch('src.agent.MCPClient.resolve_chat')
    async def test_test_connection_success(self, mock_resolve):
        mock_resolve.return_value = {'title': 'Test Chat'}
        result = await self.agent.test_connection()
        self.assertTrue(result)
        
    @patch('src.agent.MCPClient.resolve_chat', return_value=None)
    async def test_test_connection_failure(self, mock_resolve):
        result = await self.agent.test_connection()
        self.assertFalse(result)

    def test_should_process_message_pass(self):
        message = {
            'text': 'This is an important message with urgent content',
            'from': {'display': 'TestUser'}
        }
        result = self.agent.should_process_message(message)
        self.assertTrue(result)
        
    def test_should_process_message_fail_length(self):
        message = {
            'text': 'Short',
            'from': {'display': 'TestUser'}
        }
        result = self.agent.should_process_message(message)
        self.assertFalse(result)
        
    def test_should_process_message_fail_keyword(self):
        message = {
            'text': 'This message has no keywords',
            'from': {'display': 'TestUser'}
        }
        result = self.agent.should_process_message(message)
        self.assertFalse(result)

    @patch('src.agent.AsyncOpenAI')
    async def test_analyze_sentiment_and_intent(self, mock_openai):
        mock_client = Mock()
        mock_openai.return_value = mock_client
        mock_response = Mock()
        mock_response.choices = [Mock()]
        mock_response.choices[0].message.content = '{"sentiment": "positive", "intent": "praise", "confidence": 0.8}'
        mock_client.chat.completions.create.return_value = mock_response
        
        message = {'text': 'Great job!'}
        result = await self.agent.analyze_sentiment_and_intent(message)
        self.assertEqual(result['sentiment'], 'positive')
        
    @patch('src.agent.AsyncOpenAI')
    async def test_extract_features(self, mock_openai):
        mock_client = Mock()
        mock_openai.return_value = mock_client
        mock_response = Mock()
        mock_response.choices = [Mock()]
        mock_response.choices[0].message.content = '{"entities": ["Company"], "topics": ["Business"], "urgency": "high", "dates": []}'
        mock_client.chat.completions.create.return_value = mock_response
        
        message = {'text': 'Company meeting tomorrow'}
        result = await self.agent.extract_features(message)
        self.assertIn('Company', result['entities'])
        
    @patch('src.agent.AsyncOpenAI')
    async def test_generate_response(self, mock_openai):
        mock_client = Mock()
        mock_openai.return_value = mock_client
        mock_response = Mock()
        mock_response.choices = [Mock()]
        mock_response.choices[0].message.content = 'Спасибо за ваше сообщение!'
        mock_client.chat.completions.create.return_value = mock_response
        
        message = {'text': 'Hello', 'from': {'display': 'User'}}
        result = await self.agent.generate_response(message)
        self.assertIsInstance(result, str)

    @patch('src.agent.MCPClient.send_message')
    async def test_send_auto_response(self, mock_send):
        mock_send.return_value = {'success': True}
        message = {'text': 'Hello', 'from': {'display': 'User'}}
        await self.agent.send_auto_response('@test', message)
        mock_send.assert_called_once()
        
    @patch('src.agent.MCPClient.send_message')
    async def test_send_notification(self, mock_send):
        mock_send.return_value = {'success': True}
        await self.agent.send_notification('Test notification')
        mock_send.assert_called_once()
        
    @patch('src.agent.MCPClient.forward_message')
    async def test_forward_message_to_admin(self, mock_forward):
        mock_forward.return_value = {'success': True}
        message = {'id': 123, 'text': 'Important message'}
        await self.agent.forward_message_to_admin(message, '@source')
        mock_forward.assert_called_once_with('@source', '@admin', 123)

class TestMCPClient(unittest.TestCase):
    def setUp(self):
        self.client = MCPClient("http://localhost:3000")

    def test_init(self):
        self.assertEqual(self.client.server_url, "http://localhost:3000")
        self.assertIsNone(self.client.session)

if __name__ == "__main__":
    unittest.main()
