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
    phoneNumber: process.env.TELEGRAM_PHONE_NUMBER
  }
};

// Проверка наличия обязательных параметров
if (!config.telegram.apiId || !config.telegram.apiHash || !config.telegram.phoneNumber) {
  console.error("Missing required environment variables: TELEGRAM_API_ID, TELEGRAM_API_HASH, TELEGRAM_PHONE_NUMBER");
  process.exit(1);
}
