import { logError } from '../utils.js';

/**
 * Создает обработчики для инструментов MCP сервера Telegram.
 * @param {TelegramClient} client - Инициализированный клиент Telegram.
 * @returns {Object} Объект с методами list и call для инструментов.
 */
export function createToolsHandler(client) {
  const toolsList = [
    {
      name: 'resolve_chat',
      description: 'Resolve chat information by ID, username, or phone number.',
      inputSchema: {
        type: 'object',
        properties: {
          chatId: { type: ['string', 'number'], description: 'Chat identifier (ID, username, or phone)' }
        },
        required: ['chatId']
      }
    },
    {
      name: 'get_chat_history',
      description: 'Get chat message history with pagination.',
      inputSchema: {
        type: 'object',
        properties: {
          chatId: { type: ['string', 'number'], description: 'Chat identifier' },
          limit: { type: 'number', description: 'Number of messages to retrieve', default: 50 },
          offset: { type: 'number', description: 'Offset for pagination', default: 0 }
        },
        required: ['chatId']
      }
    },
    {
      name: 'send_message',
      description: 'Send a text message to a chat.',
      inputSchema: {
        type: 'object',
        properties: {
          chatId: { type: ['string', 'number'], description: 'Chat identifier' },
          text: { type: 'string', description: 'Message text' }
        },
        required: ['chatId', 'text']
      }
    },
    {
      name: 'forward_message',
      description: 'Forward a message from one chat to another.',
      inputSchema: {
        type: 'object',
        properties: {
          fromChatId: { type: ['string', 'number'], description: 'Source chat identifier' },
          messageId: { type: 'number', description: 'Message ID to forward' },
          toChatId: { type: ['string', 'number'], description: 'Destination chat identifier' }
        },
        required: ['fromChatId', 'messageId', 'toChatId']
      }
    },
    {
      name: 'mark_read',
      description: 'Mark messages as read in a chat.',
      inputSchema: {
        type: 'object',
        properties: {
          chatId: { type: ['string', 'number'], description: 'Chat identifier' },
          messageIds: { type: 'array', items: { type: 'number' }, description: 'Array of message IDs to mark as read' }
        },
        required: ['chatId', 'messageIds']
      }
    },
    {
      name: 'get_unread_count',
      description: 'Get the total number of unread messages.',
      inputSchema: {
        type: 'object',
        properties: {},
        required: []
      }
    }
  ];

  /**
   * Обработчик для tools.list.
   * @returns {Promise<Array>} Список инструментов.
   */
  async function list() {
    return toolsList;
  }

  /**
   * Обработчик для tools.call.
   * @param {Object} params - Параметры вызова.
   * @param {string} params.name - Имя инструмента.
   * @param {Object} params.arguments - Аргументы инструмента.
   * @returns {Promise<string>} Результат выполнения инструмента в JSON строке.
   */
  async function call({ name, arguments: params }) {
    try {
      switch (name) {
        case 'resolve_chat':
          const entity = await client.getEntity(params.chatId);
          return JSON.stringify(entity);

        case 'get_chat_history':
          const messages = await client.getMessages(params.chatId, { limit: params.limit || 50, offset: params.offset || 0 });
          // TODO: Implement pagination for history
          return JSON.stringify(messages.map(m => ({ id: m.id, text: m.message, date: m.date })));

        case 'send_message':
          const result = await client.sendMessage(params.chatId, { message: params.text });
          return JSON.stringify({ messageId: result.id });

        case 'forward_message':
          const forwardResult = await client.forwardMessages(params.toChatId, [params.messageId], { fromPeer: params.fromChatId });
          return JSON.stringify({ forwardedId: forwardResult[0].id });

        case 'mark_read':
          await client.readMessages(params.messageIds);
          return JSON.stringify({ success: true });

        case 'get_unread_count':
          const dialogs = await client.getDialogs();
          let unread = 0;
          for (const dialog of dialogs) {
            if (dialog.unreadCount) unread += dialog.unreadCount;
          }
          return JSON.stringify({ unreadCount: unread });

        default:
          return JSON.stringify({ error: 'Unknown tool' });
      }
    } catch (error) {
      logError(error);
      return JSON.stringify({ error: error.message });
    }
  }

  return { list, call };
}
