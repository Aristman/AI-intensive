import 'dotenv/config';
import express from 'express';
import morgan from 'morgan';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { TelegramClient, Api } from 'telegram';
import { StringSession } from 'telegram/sessions/index.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PORT = process.env.PORT ? Number(process.env.PORT) : 3000;
const HOST = process.env.HOST || '0.0.0.0';
const APP_ID = Number(process.env.TG_APP_ID || process.env.APP_ID || 0);
const API_HASH = process.env.TG_API_HASH || process.env.API_HASH || '';
const SESSION_FILE = process.env.TG_SESSION_FILE || path.join(__dirname, 'session.txt');

if (!APP_ID || !API_HASH) {
  console.error('Missing TG_APP_ID / TG_API_HASH in environment');
  process.exit(1);
}

async function tgGetUnreadCount(input = {}) {
  const c = await ensureClient();
  const chat = normalizeChat(input.chat || input.input || input);
  try {
    // Use InputDialogPeer wrapper as required by GetPeerDialogs
    const inputPeer = await c.getInputEntity(chat);
    const resp = await c.invoke(new Api.messages.GetPeerDialogs({ peers: [new Api.InputDialogPeer({ peer: inputPeer })] }));
    const dlg = Array.isArray(resp.dialogs) && resp.dialogs.length ? resp.dialogs[0] : null;
    const unread = dlg && typeof dlg.unreadCount === 'number' ? dlg.unreadCount : 0;
    const unreadMentions = dlg && typeof dlg.unreadMentionsCount === 'number' ? dlg.unreadMentionsCount : undefined;
    return { chat, unread, unread_mentions: unreadMentions };
  } catch (e) {
    console.error('tg.get_unread_count error for', chat, e?.message || e);
    return { chat, unread: 0 };
  }
}

function loadSessionString(filePath) {
  try {
    if (fs.existsSync(filePath)) {
      return fs.readFileSync(filePath, 'utf8').trim();
    }
    return '';
  } catch (e) {
    return '';
  }
}

let client = null;
let ready = false;

async function ensureClient() {
  if (client && ready) return client;

  const sessionString = loadSessionString(SESSION_FILE);
  if (!sessionString) {
    throw Object.assign(new Error('Telegram session not found. Run auth first.'), { code: 'NEEDS_AUTH' });
  }

  client = new TelegramClient(new StringSession(sessionString), APP_ID, API_HASH, {
    connectionRetries: 3,
    deviceModel: 'Telegram HTTP MCP',
    systemVersion: '1.0',
    appVersion: '0.1.0'
  });

  if (!client.connected) {
    await client.connect();
  }
  ready = true;
  return client;
}

function normalizeChat(value) {
  if (!value) return value;
  const s = String(value).trim();
  if (!s) return s;
  if (s.startsWith('http://') || s.startsWith('https://') || s.includes('/')) return s;
  if (/^-?\d+$/.test(s)) return s; // numeric id
  if (s.startsWith('@')) return s.slice(1);
  return s;
}

async function tgResolveChat(input) {
  const c = await ensureClient();
  const query = normalizeChat(input);
  const entity = await c.getEntity(query);

  const base = {
    id: entity.id ? String(entity.id) : undefined,
    username: entity.username || undefined,
    title: entity.title || entity.firstName || entity.lastName || undefined,
  };

  // Determine type
  let type = 'unknown';
  if ('firstName' in entity || 'lastName' in entity) type = 'user';
  else if (entity.megagroup) type = 'supergroup';
  else if (entity.broadcast) type = 'channel';
  else if ('title' in entity) type = 'chat';

  return { ...base, type };
}

async function tgFetchHistory(input = {}) {
  const c = await ensureClient();
  const chat = normalizeChat(input.chat || input.input || input);
  const limit = Number(input.limit || input.page_size || 50);
  const offsetId = input.offset_id ? Number(input.offset_id) : undefined;
  const minId = input.min_id ? Number(input.min_id) : undefined;
  const maxId = input.max_id ? Number(input.max_id) : undefined;

  const entity = await c.getEntity(chat);
  const messages = await c.getMessages(entity, {
    limit,
    offsetId,
    minId,
    maxId,
    // fromDate/toDate are not directly supported in getMessages options;
    // can be implemented with iterMessages if needed later.
  });

  const mapped = messages.map(m => ({
    id: m.id,
    text: m.message || '',
    date: m.date ? new Date(m.date * 1000).toISOString() : undefined,
    from: {
      id: m.senderId ? String(m.senderId) : undefined,
      display: m.sender && (m.sender.username || m.sender.firstName || m.sender.lastName) || undefined
    }
  }));

  return { chat: chat, messages: mapped };
}

async function tgSendMessage(input = {}) {
  const c = await ensureClient();
  const chat = normalizeChat(input.chat || input.input || input);
  const message = String(input.message || '');
  const entity = await c.getEntity(chat);
  const res = await c.sendMessage(entity, { message });
  return { ok: true, id: res.id };
}

async function tgForwardMessage(input = {}) {
  const c = await ensureClient();
  const fromChat = normalizeChat(input.from_chat || input.from || input.source);
  const toChat = normalizeChat(input.to_chat || input.to || input.target);
  const messageId = Number(input.message_id || input.id);
  const fromEntity = await c.getEntity(fromChat);
  const toEntity = await c.getEntity(toChat);
  await c.forwardMessages(toEntity, { fromPeer: fromEntity, messages: [messageId] });
  return { ok: true };
}

async function tgReadMessages(input = {}) {
  const c = await ensureClient();
  const chat = normalizeChat(input.chat || input.input || input);
  const entity = await c.getEntity(chat);
  // Support either a list of ids or max_id semantics
  const ids = Array.isArray(input.ids) ? input.ids.map(Number) : undefined;
  const maxId = input.max_id ? Number(input.max_id) : undefined;

  if (ids && ids.length) {
    // GramJS doesn't expose readMessages(entity, ids) directly; use invoke
    await c.invoke(new Api.messages.ReadMessages({ id: ids }));
    return { ok: true, count: ids.length };
  }

  // Mark up to maxId as read using ReadHistory
  await c.invoke(new Api.messages.ReadHistory({ peer: entity, maxId: maxId || 0 }));
  return { ok: true, max_id: maxId || 0 };
}

const app = express();
app.use(express.json({ limit: '1mb' }));
app.use(morgan('combined'));

app.get('/health', async (req, res) => {
  try {
    await ensureClient();
    res.json({ ok: true, status: 'ready' });
  } catch (e) {
    if (e && e.code === 'NEEDS_AUTH') return res.status(503).json({ ok: false, error: 'needs_auth' });
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.post('/tools', async (req, res) => {
  const { tool, input } = req.body || {};
  try {
    if (!tool) return res.status(400).json({ error: 'tool is required' });

    switch (tool) {
      case 'tg.resolve_chat': {
        const result = await tgResolveChat(input?.input || input?.chat || input);
        return res.json(result);
      }
      case 'tg.fetch_history': {
        const result = await tgFetchHistory(input || {});
        return res.json(result);
      }
      case 'tg.send_message': {
        const result = await tgSendMessage(input || {});
        return res.json(result);
      }
      case 'tg.forward_message': {
        const result = await tgForwardMessage(input || {});
        return res.json(result);
      }
      case 'tg.read_messages': {
        const result = await tgReadMessages(input || {});
        return res.json(result);
      }
      case 'tg.get_unread_count': {
        const result = await tgGetUnreadCount(input || {});
        return res.json(result);
      }
      default:
        return res.status(400).json({ error: `Unknown tool: ${tool}` });
    }
  } catch (e) {
    if (e && e.code === 'NEEDS_AUTH') return res.status(503).json({ error: 'needs_auth' });
    console.error(e);
    return res.status(500).json({ error: String(e.message || e) });
  }
});

app.listen(PORT, HOST, () => {
  console.log(`Telegram HTTP MCP listening on http://${HOST}:${PORT}`);
});
