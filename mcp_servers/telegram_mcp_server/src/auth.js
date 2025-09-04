import { config as loadEnv } from 'dotenv';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';
import input from 'input';
import { TelegramClient } from 'telegram';
import { StringSession } from 'telegram/sessions/index.js';

// Load .env from project root (../.env relative to this file)
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
loadEnv({ path: path.resolve(__dirname, '../.env') });

// Support multiple env var names for convenience
const APP_ID = Number(process.env.TELEGRAM_API_ID || process.env.TG_APP_ID || process.env.APP_ID || 0);
const API_HASH = process.env.TELEGRAM_API_HASH || process.env.TG_API_HASH || process.env.API_HASH || '';
const PHONE_NUMBER = process.env.TELEGRAM_PHONE_NUMBER || process.env.TG_PHONE_NUMBER || '';
const SESSION_FILE = process.env.TELEGRAM_SESSION_FILE || path.join(__dirname, 'session.txt');

if (!APP_ID || !API_HASH) {
  console.error('Missing TELEGRAM_API_ID / TELEGRAM_API_HASH (or TG_APP_ID / TG_API_HASH) in environment');
  process.exit(1);
}

function saveSessionString(filePath, str) {
  fs.writeFileSync(filePath, str, 'utf8');
  console.log('Session saved to', filePath);
}

(async () => {
  const client = new TelegramClient(new StringSession(''), APP_ID, API_HASH, {
    connectionRetries: 5,
    deviceModel: 'Telegram MCP Server',
    systemVersion: '1.0',
    appVersion: '0.1.0',
  });

  await client.start({
    phoneNumber: async () => PHONE_NUMBER || (await input.text('Please enter your phone number: ')),
    password: async () => await input.text('Please enter your 2FA password (if any): ', { replace: '*' }),
    phoneCode: async () => await input.text('Please enter the code you received: '),
    onError: (err) => console.error(err),
  });

  const sessionString = client.session.save();
  saveSessionString(SESSION_FILE, sessionString);
  console.log('You are now logged in.');
  await client.disconnect();
})();
