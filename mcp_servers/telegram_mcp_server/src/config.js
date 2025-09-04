import { config as loadEnv } from 'dotenv';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// Load environment variables from .env file if it exists
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
loadEnv({ path: path.resolve(__dirname, '../.env') });

/**
 * Конфигурация сервера MCP для Telegram.
 * @typedef {Object} Config
 * @property {string} name - Имя сервера.
 * @property {string} version - Версия сервера.
 * @property {Object} telegram - Параметры для Telegram API.
 * @property {string} telegram.apiId - API ID для Telegram.
 * @property {string} telegram.apiHash - API Hash для Telegram.
 * @property {string} telegram.phoneNumber - Номер телефона для аутентификации.
 */

/**
 * Объект конфигурации сервера.
 * Получает критически важные параметры из переменных окружения.
 * @type {Config}
 */
export const config = {
  name: "telegram-mcp-server",
  version: "0.1.0",
  telegram: {
    apiId: process.env.TELEGRAM_API_ID,
    apiHash: process.env.TELEGRAM_API_HASH,
    phoneNumber: process.env.TELEGRAM_PHONE_NUMBER,
    botToken: process.env.TELEGRAM_BOT_TOKEN
  }
};

// Проверка наличия обязательных параметров
const hasUserAuth = config.telegram.apiId && config.telegram.apiHash && config.telegram.phoneNumber;
const hasBotAuth = config.telegram.botToken;

if (!hasUserAuth && !hasBotAuth) {
  console.error("Missing required environment variables. Either provide:");
  console.error("  For user authentication: TELEGRAM_API_ID, TELEGRAM_API_HASH, TELEGRAM_PHONE_NUMBER");
  console.error("  Or for bot authentication: TELEGRAM_BOT_TOKEN");
  process.exit(1);
}
