import { WebSocketServer } from 'ws';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// Simple WS <-> STDIO bridge for MCP server (yandex_search_mcp_server)
// Listens on ws://localhost:8765 and spawns the STDIO server at ../src/index.js

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const PORT = parseInt(process.env.BRIDGE_PORT || '8765', 10);
const SERVER_CWD = resolve(__dirname, '..'); // parent dir = yandex_search_mcp_server
const SERVER_ENTRY = 'src/index.js';

const wss = new WebSocketServer({ port: PORT });
console.log(`[bridge] WS bridge listening on ws://localhost:${PORT}`);
console.log(`[bridge] Spawning STDIO MCP server from: ${SERVER_CWD}/${SERVER_ENTRY}`);

wss.on('connection', (ws) => {
  const child = spawn(process.execPath, [SERVER_ENTRY], {
    cwd: SERVER_CWD,
    stdio: ['pipe', 'pipe', 'pipe'],
    env: process.env, // pass through YANDEX_API_KEY, YANDEX_FOLDER_ID, etc.
  });

  let buffer = Buffer.alloc(0);

  // STDIO -> WS: parse Content-Length framed messages
  child.stdout.on('data', (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    while (true) {
      const headerEnd = buffer.indexOf('\r\n\r\n');
      if (headerEnd === -1) break;
      const header = buffer.slice(0, headerEnd).toString('utf8');
      const m = header.match(/Content-Length:\s*(\d+)/i);
      if (!m) {
        // Drop header and continue
        buffer = buffer.slice(headerEnd + 4);
        continue;
      }
      const len = parseInt(m[1], 10);
      const start = headerEnd + 4;
      if (buffer.length < start + len) break; // wait for rest
      const body = buffer.slice(start, start + len).toString('utf8');
      try {
        ws.send(body);
      } catch (e) {
        console.error('[bridge] WS send error:', e);
      }
      buffer = buffer.slice(start + len);
    }
  });

  child.stderr.on('data', (d) => {
    // Forward MCP stderr to bridge console for visibility
    console.error('[mcp:stderr]', d.toString());
  });

  // WS -> STDIO: frame JSON with Content-Length
  ws.on('message', (data) => {
    const payload = typeof data === 'string' ? data : data.toString();
    const framed = `Content-Length: ${Buffer.byteLength(payload, 'utf8')}\r\n\r\n${payload}`;
    try {
      child.stdin.write(framed);
    } catch (e) {
      console.error('[bridge] Failed to write to child stdin:', e);
    }
  });

  const closeAll = () => {
    try { child.kill(); } catch {}
    try { ws.close(); } catch {}
  };

  ws.on('close', closeAll);
  ws.on('error', closeAll);
  child.on('exit', (code, signal) => {
    console.log(`[bridge] MCP process exited code=${code} signal=${signal}`);
    try { ws.close(); } catch {}
  });
});
