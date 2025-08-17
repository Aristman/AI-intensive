import 'dotenv/config';
import { WebSocketServer } from 'ws';
import axios from 'axios';

const PORT = process.env.PORT ? Number(process.env.PORT) : 3001;
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;

if (!GITHUB_TOKEN) {
  console.warn('[MCP] Warning: GITHUB_TOKEN is not set. create_issue and private repos will fail.');
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
          serverInfo: { name: 'mcp-github-server', version: '1.0.0' },
          capabilities: { tools: true },
        }));
      }
      if (method === 'tools/list') {
        return send(ws, makeResult(id, {
          tools: [
            { name: 'get_repo', description: 'Get GitHub repo info', inputSchema: { owner: 'string', repo: 'string' } },
            { name: 'search_repos', description: 'Search GitHub repos', inputSchema: { query: 'string' } },
            { name: 'create_issue', description: 'Create GitHub issue', inputSchema: { owner: 'string', repo: 'string', title: 'string', body: 'string?' } },
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
