import 'dotenv/config';
import { WebSocketServer } from 'ws';
import axios from 'axios';

const PORT = process.env.PORT ? Number(process.env.PORT) : 3001;
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const TELEGRAM_DEFAULT_CHAT_ID = process.env.TELEGRAM_DEFAULT_CHAT_ID;

if (!GITHUB_TOKEN) {
  console.warn('[MCP] Warning: GITHUB_TOKEN is not set. create_issue and private repos will fail.');
}
if (!TELEGRAM_BOT_TOKEN) {
  console.warn('[MCP] Warning: TELEGRAM_BOT_TOKEN is not set. Telegram tools will fail.');
}

const wss = new WebSocketServer({ port: PORT });
console.log(`[MCP] Server started on ws://localhost:${PORT}`);

function send(ws, msg) {
  ws.send(JSON.stringify(msg));
}

function makeError(id, code, message, data) {
  return { jsonrpc: '2.0', id, error: { code, message, data } };
}

function makeResult(id, result) {
  return { jsonrpc: '2.0', id, result };
}

async function ghRequest(method, url, body) {
  const base = 'https://api.github.com';
  const headers = {
    Accept: 'application/vnd.github.v3+json',
    ...(GITHUB_TOKEN ? { Authorization: `token ${GITHUB_TOKEN}` } : {}),
  };
  const resp = await axios({ method, url: base + url, data: body, headers });
  return resp.data;
}

async function tgRequest(methodName, payload) {
  if (!TELEGRAM_BOT_TOKEN) throw new Error('TELEGRAM_BOT_TOKEN is not configured on server');
  const url = `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/${methodName}`;
  const resp = await axios.post(url, payload);
  const data = resp.data;
  if (data && data.ok === false) {
    throw new Error(`Telegram API error: ${JSON.stringify(data)}`);
  }
  return data?.result ?? data;
}

async function handleToolCall(name, args) {
  switch (name) {
    case 'get_repo': {
      const { owner, repo } = args || {};
      if (!owner || !repo) throw new Error('owner and repo are required');
      return await ghRequest('GET', `/repos/${owner}/${repo}`);
    }
    case 'search_repos': {
      const { query } = args || {};
      if (!query) throw new Error('query is required');
      const data = await ghRequest('GET', `/search/repositories?q=${encodeURIComponent(query)}`);
      return data.items || [];
    }
    case 'create_issue': {
      if (!GITHUB_TOKEN) throw new Error('GITHUB_TOKEN is not configured on server');
      const { owner, repo, title, body } = args || {};
      if (!owner || !repo || !title) throw new Error('owner, repo, title are required');
      return await ghRequest('POST', `/repos/${owner}/${repo}/issues`, { title, body });
    }
    case 'list_issues': {
      const { owner, repo, state = 'open', per_page = 5, page = 1 } = args || {};
      if (!owner || !repo) throw new Error('owner and repo are required');
      const qs = new URLSearchParams({ state: String(state), per_page: String(per_page), page: String(page) }).toString();
      const items = await ghRequest('GET', `/repos/${owner}/${repo}/issues?${qs}`);
      // Filter out PRs
      const issuesOnly = Array.isArray(items) ? items.filter((it) => !it.pull_request) : [];
      return issuesOnly;
    }
    case 'tg_send_message': {
      const { chat_id, text, parse_mode, disable_web_page_preview } = args || {};
      if (!text) throw new Error('text is required');
      const cid = chat_id ?? TELEGRAM_DEFAULT_CHAT_ID;
      if (!cid) throw new Error('chat_id is required (or set TELEGRAM_DEFAULT_CHAT_ID)');
      return await tgRequest('sendMessage', { chat_id: cid, text, parse_mode, disable_web_page_preview });
    }
    case 'tg_send_photo': {
      const { chat_id, photo, caption, parse_mode } = args || {};
      if (!photo) throw new Error('photo (URL or file_id) is required');
      const cid = chat_id ?? TELEGRAM_DEFAULT_CHAT_ID;
      if (!cid) throw new Error('chat_id is required (or set TELEGRAM_DEFAULT_CHAT_ID)');
      return await tgRequest('sendPhoto', { chat_id: cid, photo, caption, parse_mode });
    }
    case 'tg_get_updates': {
      const { offset, timeout, allowed_updates } = args || {};
      return await tgRequest('getUpdates', { offset, timeout, allowed_updates });
    }
    case 'create_issue_and_notify': {
      if (!GITHUB_TOKEN) throw new Error('GITHUB_TOKEN is not configured on server');
      const { owner, repo, title, body, chat_id, message_template } = args || {};
      if (!owner || !repo || !title) throw new Error('owner, repo, title are required');
      const issue = await ghRequest('POST', `/repos/${owner}/${repo}/issues`, { title, body });
      const cid = chat_id ?? TELEGRAM_DEFAULT_CHAT_ID;
      if (!cid) throw new Error('chat_id is required (or set TELEGRAM_DEFAULT_CHAT_ID)');
      const issueUrl = issue?.html_url || issue?.url || '';
      const defaultMsg = `New GitHub issue created: ${owner}/${repo}\n#${issue?.number ?? ''} ${title}\n${issueUrl}`;
      const text = message_template || defaultMsg;
      await tgRequest('sendMessage', { chat_id: cid, text });
      return { issue, notified: true };
    }
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

wss.on('connection', (ws) => {
  ws.on('message', async (raw) => {
    let msg;
    try { msg = JSON.parse(raw.toString()); } catch {
      return send(ws, makeError(null, -32700, 'Parse error'));
    }

    const { id, method, params } = msg;
    if (!method) {
      return send(ws, makeError(id ?? null, -32600, 'Invalid Request'));
    }

    try {
      if (method === 'initialize') {
        return send(ws, makeResult(id, {
          serverInfo: { name: 'mcp-github-telegram-server', version: '1.1.0' },
          capabilities: { tools: true },
        }));
      }
      if (method === 'tools/list') {
        return send(ws, makeResult(id, {
          tools: [
            { name: 'get_repo', description: 'Get GitHub repo info', inputSchema: { owner: 'string', repo: 'string' } },
            { name: 'search_repos', description: 'Search GitHub repos', inputSchema: { query: 'string' } },
            { name: 'create_issue', description: 'Create GitHub issue', inputSchema: { owner: 'string', repo: 'string', title: 'string', body: 'string?' } },
            { name: 'list_issues', description: 'List issues for a repo (no PRs)', inputSchema: { owner: 'string', repo: 'string', state: 'string?', per_page: 'number?', page: 'number?' } },
            { name: 'tg_send_message', description: 'Send Telegram text message', inputSchema: { chat_id: 'string?', text: 'string', parse_mode: 'string?', disable_web_page_preview: 'boolean?' } },
            { name: 'tg_send_photo', description: 'Send Telegram photo by URL or file_id', inputSchema: { chat_id: 'string?', photo: 'string', caption: 'string?', parse_mode: 'string?' } },
            { name: 'tg_get_updates', description: 'Get Telegram updates (long polling)', inputSchema: { offset: 'number?', timeout: 'number?', allowed_updates: 'string[]?' } },
            { name: 'create_issue_and_notify', description: 'Create GitHub issue and notify Telegram chat', inputSchema: { owner: 'string', repo: 'string', title: 'string', body: 'string?', chat_id: 'string?', message_template: 'string?' } },
          ],
        }));
      }
      if (method === 'tools/call') {
        const { name, arguments: args } = params || {};
        const result = await handleToolCall(name, args);
        return send(ws, makeResult(id, { name, result }));
      }

      return send(ws, makeError(id, -32601, 'Method not found'));
    } catch (err) {
      const message = err?.response?.data || err?.message || String(err);
      return send(ws, makeError(id, -32000, 'Tool call failed', message));
    }
  });
});
