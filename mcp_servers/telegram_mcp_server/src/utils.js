import { TelegramClient } from 'telegram';
import { StringSession } from 'telegram/sessions/index.js';

/**
 * Асинхронная функция для инициализации и аутентификации клиента Telegram MTProto.
 * @param {Object} telegramConfig - Конфигурация Telegram (apiId, apiHash, phoneNumber или botToken).
 * @returns {Promise<TelegramClient>} Инициализированный клиент Telegram.
 * @throws {Error} Если инициализация не удалась.
 */
export async function setupTelegramClient(telegramConfig) {
  const { apiId, apiHash, phoneNumber, botToken } = telegramConfig;

  // Создаем сессию для сохранения состояния
  const session = new StringSession('');

  let client;

  if (botToken) {
    // Bot authentication
    console.error('Using bot authentication with token');
    client = new TelegramClient(session, parseInt(apiId || '0'), apiHash || '', {
      connectionRetries: 5,
    });

    try {
      await client.start({
        botAuthToken: botToken
      });
      console.error('Bot client initialized successfully.');
      return client;
    } catch (error) {
      logError(error);
      throw error;
    }
  } else {
    // User authentication
    console.error('Using user authentication with phone number');
    client = new TelegramClient(session, parseInt(apiId), apiHash, {
      connectionRetries: 5,
    });

    try {
      // Подключаемся к серверу
      await client.connect();

      // Проверяем авторизацию
      if (!(await client.isUserAuthorized())) {
        // TODO: Обработка 2FA - требуется код подтверждения
        // В реальной реализации нужно получить код от пользователя
        // Пока что логируем и бросаем ошибку
        logError(new Error('User not authorized. 2FA code required.'));
        throw new Error('User not authorized. Please provide 2FA code in future implementation.');
      }

      console.error('User client initialized successfully.');
      return client;
    } catch (error) {
      logError(error);
      throw error;
    }
  }
}

/**
 * Асинхронная функция для получения InputPeer по идентификатору чата.
 * @param {TelegramClient} client - Клиент Telegram.
 * @param {string|number} identifier - Идентификатор чата (ID, username или телефон).
 * @returns {Promise<Object>} Объект InputPeer.
 * @throws {Error} Если не удалось получить InputPeer.
 */
export async function getInputEntity(client, identifier) {
  try {
    const entity = await client.getInputEntity(identifier);
    return entity;
  } catch (error) {
    logError(error);
    throw new Error(`Failed to resolve chat identifier: ${identifier}`);
  }
}

/**
 * Функция для логирования ошибок в stderr.
 * @param {Error|string} error - Ошибка для логирования.
 */
export function logError(error) {
  console.error('Error:', error.message || error);
}
