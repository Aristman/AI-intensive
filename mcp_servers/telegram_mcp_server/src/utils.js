import { TelegramClient } from 'telegram';
import { StringSession } from 'telegram/sessions/index.js';
import input from 'input';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * Асинхронная функция для инициализации и аутентификации клиента Telegram MTProto.
 * @param {Object} telegramConfig - Конфигурация Telegram (apiId, apiHash, phoneNumber или botToken).
 * @returns {Promise<TelegramClient>} Инициализированный клиент Telegram.
 * @throws {Error} Если инициализация не удалась.
 */
export async function setupTelegramClient(telegramConfig) {
  const { apiId, apiHash, phoneNumber, botToken } = telegramConfig;

  // Определим путь к файлу сессии
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = path.dirname(__filename);
  const sessionFile = process.env.TELEGRAM_SESSION_FILE || path.resolve(__dirname, 'session.txt');

  async function readSessionString() {
    try {
      const data = await fs.readFile(sessionFile, 'utf8');
      return String(data || '').trim();
    } catch {
      return '';
    }
  }

  async function writeSessionString(str) {
    try {
      await fs.writeFile(sessionFile, str, 'utf8');
      console.error(`Session saved to ${sessionFile}`);
    } catch (e) {
      console.error('Failed to save session:', e?.message || e);
    }
  }

  // Загружаем сохранённую сессию, если есть
  const existingSession = await readSessionString();
  const session = new StringSession(existingSession);

  let client;

  if (botToken) {
    // Bot authentication
    console.error('Using bot authentication with token');
    client = new TelegramClient(session, parseInt(apiId || '0'), apiHash || '', {
      connectionRetries: 5,
      deviceModel: 'Telegram MCP Server',
      systemVersion: '1.0',
      appVersion: '0.1.0',
    });

    try {
      await client.start({ botAuthToken: botToken });
      // Сохраним сессию на будущее
      await writeSessionString(client.session.save());
      console.error('Bot client initialized successfully.');
      return client;
    } catch (error) {
      logError(error);
      throw error;
    }
  } else {
    // User authentication (интерактивная 2FA)
    console.error('Using user authentication (interactive)');
    client = new TelegramClient(session, parseInt(apiId), apiHash, {
      connectionRetries: 5,
      deviceModel: 'Telegram MCP Server',
      systemVersion: '1.0',
      appVersion: '0.1.0',
    });

    try {
      await client.start({
        phoneNumber: async () => {
          if (phoneNumber) return String(phoneNumber);
          return await input.text('Please enter your phone number: ');
        },
        password: async () => {
          // 2FA password (если включена)
          return await input.text('Please enter your 2FA password (if any): ', { replace: '*' });
        },
        phoneCode: async () => {
          // Код из SMS/Telegram
          return await input.text('Please enter the code you received: ');
        },
        onError: (err) => console.error(err),
      });

      // Сохраним сессию, чтобы не спрашивать код повторно
      await writeSessionString(client.session.save());

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
