import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { TelegramClient } from 'telegram';
import { StringSession } from 'telegram/sessions/index.js';
import input from 'input';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const APP_ID = Number(process.env.TG_APP_ID || process.env.APP_ID || 0);
const API_HASH = process.env.TG_API_HASH || process.env.API_HASH || '';
const SESSION_FILE = process.env.TG_SESSION_FILE || path.join(__dirname, 'session.txt');

if (!APP_ID || !API_HASH) {
  console.error('Missing TG_APP_ID / TG_API_HASH in environment');
  process.exit(1);
}

function saveSessionString(filePath, str) {
  fs.writeFileSync(filePath, str, 'utf8');
  console.log('Session saved to', filePath);
}

(async () => {
  const client = new TelegramClient(new StringSession(''), APP_ID, API_HASH, {
    connectionRetries: 3,
    deviceModel: 'Telegram HTTP MCP',
    systemVersion: '1.0',
    appVersion: '0.1.0'
  });

  await client.start({
    phoneNumber: async () => await input.text('Please enter your phone number: '),
    password: async () => await input.text('Please enter your 2FA password (if any): ', { replace: '*' }),
    phoneCode: async () => await input.text('Please enter the code you received: '),
    onError: (err) => console.error(err)
  });

  const sessionString = client.session.save();
  saveSessionString(SESSION_FILE, sessionString);
  console.log('You are now logged in.');
  await client.disconnect();
})();
