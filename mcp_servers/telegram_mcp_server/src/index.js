import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { config } from './config.js';
import { setupTelegramClient } from './utils.js';
import { list as listResources, read as readResource } from './handlers/resources.js';
import { createToolsHandler } from './handlers/tools.js';

/**
 * Главная функция для запуска MCP сервера Telegram.
 */
async function main() {
  try {
    // Инициализируем клиент Telegram
    const client = await setupTelegramClient(config.telegram);

    // Создаем обработчики инструментов
    const tools = createToolsHandler(client);

    // Создаем экземпляр сервера MCP
    const server = new Server({ name: config.name, version: config.version });

    // Регистрируем обработчики с использованием схем SDK
    server.setRequestHandler(ListResourcesRequestSchema, async () => {
      const resources = await listResources();
      // Ожидаемый формат: { resources: Resource[] }
      return { resources };
    });

    server.setRequestHandler(ReadResourceRequestSchema, async ({ params }) => {
      const result = await readResource({ uri: params.uri });
      // Приведение к ожидаемому формату: { contents: Content[] }
      if (Array.isArray(result?.contents)) {
        return { contents: result.contents };
      }
      return {
        contents: [
          {
            uri: params.uri,
            mimeType: 'application/json',
            text: JSON.stringify(result ?? {}),
          },
        ],
      };
    });

    server.setRequestHandler(ListToolsRequestSchema, async () => {
      const list = await tools.list();
      // Ожидаемый формат: { tools: Tool[] }
      return { tools: list };
    });

    server.setRequestHandler(CallToolRequestSchema, async ({ params }) => {
      const toolName = params.name;
      const args = params.arguments ?? {};
      const raw = await tools.call({ name: toolName, arguments: args });
      // Оборачиваем результат в текстовый контент согласно протоколу
      const text = typeof raw === 'string' ? raw : JSON.stringify(raw);
      return {
        content: [
          {
            type: 'text',
            text,
          },
        ],
      };
    });

    // Инициализируем транспорт Stdio
    const transport = new StdioServerTransport();
    await server.connect(transport);

    console.error('MCP server started successfully.');

    // Обработка graceful shutdown
    process.on('SIGINT', async () => {
      console.error('Shutting down...');
      await client.disconnect();
      process.exit(0);
    });

  } catch (error) {
    console.error('Failed to start server:', error.message || error);
    process.exit(1);
  }
}

// Запускаем сервер
main();
