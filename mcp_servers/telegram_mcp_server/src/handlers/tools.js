import { logError } from '../utils.js';

/**
 * Создает обработчики для инструментов MCP сервера Telegram.
 * @param {TelegramClient} client - Инициализированный клиент Telegram.
 * @returns {Object} Объект с методами list и call для инструментов.
 */
export function createToolsHandler(client) {
  const toolsList = [
    {
      name: 'tg.resolve_chat',
      description: 'Alias of resolve_chat (compatibility)',
      inputSchema: {
        type: 'object',
        properties: {
          input: { type: ['string', 'number'], description: 'Chat identifier (ID, username, or phone)' },
          chat: { type: ['string', 'number'], description: 'Chat identifier (alternative key)' },
          chatId: { type: ['string', 'number'], description: 'Chat identifier (alternative key)' }
        },
        required: []
      }
    },
    {
      name: 'tg.fetch_history',
      description: 'Alias of get_chat_history (compatibility)',
      inputSchema: {
        type: 'object',
        properties: {
          chat: { type: ['string', 'number'], description: 'Chat identifier' },
          page_size: { type: 'number', description: 'Page size', default: 50 },
          min_id: { type: 'number', description: 'Fetch messages with id > min_id' },
          max_id: { type: 'number', description: 'Fetch messages with id <= max_id' }
        },
        required: ['chat']
      }
    },
    {
      name: 'tg.send_message',
      description: 'Alias of send_message (compatibility)',
      inputSchema: {
        type: 'object',
        properties: {
          chat: { type: ['string', 'number'], description: 'Chat identifier' },
          message: { type: 'string', description: 'Message text' }
        },
        required: ['chat', 'message']
      }
    },
    {
      name: 'tg.forward_message',
      description: 'Alias of forward_message (compatibility)',
      inputSchema: {
        type: 'object',
        properties: {
          from_chat: { type: ['string', 'number'], description: 'Source chat identifier' },
          message_id: { type: 'number', description: 'Message ID to forward' },
          to_chat: { type: ['string', 'number'], description: 'Destination chat identifier' }
        },
        required: ['from_chat', 'message_id', 'to_chat']
      }
    },
    {
      name: 'tg.mark_read',
      description: 'Mark messages as read in a chat.',
      inputSchema: {
        type: 'object',
        properties: {
          chat: { type: ['string', 'number'], description: 'Chat identifier' },
          message_ids: { type: 'array', items: { type: 'number' }, description: 'Array of message IDs to mark as read' },
          messageIds: { type: 'array', items: { type: 'number' }, description: 'Alternative camelCase key' }
        },
        required: ['chat', 'message_ids']
      }
    },
    {
      name: 'tg.get_unread_count',
      description: 'Get the total number of unread messages.',
      inputSchema: {
        type: 'object',
        properties: {
          chat: { type: ['string', 'number'], description: 'Optional: specific chat to query' }
        },
        required: []
      }
    },
    {
      name: 'tg.get_chats',
      description: 'List available chats and basic metadata.',
      inputSchema: {
        type: 'object',
        properties: {},
        required: []
      }
    },
    {
      name: 'tg.read_messages',
      description: 'Read messages from a chat (equivalent to fetch_history).',
      inputSchema: {
        type: 'object',
        properties: {
          chat: { type: ['string', 'number'], description: 'Chat identifier' },
          page_size: { type: 'number', description: 'Page size', default: 50 },
          min_id: { type: 'number', description: 'Fetch messages with id > min_id' },
          max_id: { type: 'number', description: 'Fetch messages with id <= max_id' }
        },
        required: ['chat']
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
      // Helpers to normalize arguments from different client variants
      const chatArg = params?.chat ?? params?.chatId ?? params?.input;
      const pageSize = params?.page_size ?? params?.limit;
      const minId = params?.min_id ?? params?.minId;
      const maxId = params?.max_id ?? params?.maxId;

      switch (name) {
        case 'tg.resolve_chat':
          {
            const entity = await client.getEntity(chatArg);
            // Normalize minimal entity info expected by client
            const id = entity?.id ?? entity?.peerId?.channelId ?? entity?.peerId?.chatId ?? entity?.peerId?.userId ?? null;
            const username = entity?.username ?? entity?.user?.username ?? null;
            const title = entity?.title ?? (([entity?.firstName, entity?.lastName].filter(Boolean).join(' ')) || username || (id != null ? String(id) : null));
            const type = entity?.className ?? (entity?._ ? String(entity._) : undefined) ?? 'chat';
            return { id, username, title, type };
          }

        case 'tg.read_messages':
        case 'tg.fetch_history':
          {
            const limit = pageSize || 50;
            // Pass through known options if supported by library
            const opts = { limit };
            if (typeof minId === 'number') opts.minId = minId;
            if (typeof maxId === 'number') opts.maxId = maxId;
            // offset support (fallback)
            if (typeof params?.offset === 'number') opts.offset = params.offset;
            const raw = await client.getMessages(chatArg, opts);
            const mapped = (raw || []).map(m => ({
              id: m?.id,
              text: m?.message ?? m?.text ?? '',
              date: m?.date,
              from: {
                id: m?.senderId ?? null,
                display: (m?.sender && (m?.sender?.username || [m?.sender?.firstName, m?.sender?.lastName].filter(Boolean).join(' '))) || (m?.senderId != null ? String(m.senderId) : 'Unknown')
              }
            }));
            return { messages: mapped };
          }

        case 'tg.send_message':
          {
            const result = await client.sendMessage(chatArg, { message: params?.text ?? params?.message });
            return { message_id: result?.id ?? null };
          }

        case 'tg.forward_message':
          {
            const fromChat = params?.from_chat ?? params?.fromChatId;
            const toChat = params?.to_chat ?? params?.toChatId;
            const messageId = params?.message_id ?? params?.messageId;
            const forwardResult = await client.forwardMessages(toChat, [messageId], { fromPeer: fromChat });
            const first = Array.isArray(forwardResult) ? forwardResult[0] : forwardResult;
            return { forwarded_id: first?.id ?? null };
          }

        case 'tg.mark_read':
          {
            const ids = params?.message_ids ?? params?.messageIds ?? [];
            await client.readMessages(ids);
            return { success: true };
          }

        case 'tg.get_unread_count':
          {
            const dialogs = await client.getDialogs();
            let unread = 0;
            if (chatArg) {
              for (const d of dialogs) {
                if (d?.id === chatArg || d?.entity?.username === chatArg) {
                  unread += d?.unreadCount || 0;
                }
              }
            } else {
              for (const d of dialogs) {
                if (d?.unreadCount) unread += d.unreadCount;
              }
            }
            return { unread };
          }

        case 'tg.get_chats':
          {
            const chats = await client.getDialogs();
            const mapped = chats.map(d => ({
              id: d?.id,
              title: d?.title,
              username: d?.entity?.username || null,
              unread: d?.unreadCount || 0
            }));
            return mapped;
          }

        default:
          return { error: 'Unknown tool' };
      }
    } catch (error) {
      logError(error);
      return { error: error?.message || String(error) };
    }
  }

  return { list, call };
}
