import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
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
    const server = new Server(config.name, config.version);

    // Регистрируем обработчики
    server.setRequestHandler('resources/list', listResources);
    server.setRequestHandler('resources/read', readResource);
    server.setRequestHandler('tools/list', tools.list);
    server.setRequestHandler('tools/call', tools.call);

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
