// Yandex Search MCP Server (STDIO, ESM)
// - JSON-RPC 2.0 over stdio with Content-Length framing
// - Tools: yandex_search_web
// - Resources: stub list/read
// - Auth: Authorization: Api-Key <YANDEX_API_KEY>, x-folder-id: <YANDEX_FOLDER_ID>
// Logs and diagnostics -> stderr only.

import { config, validateConfig } from './config.js';
import { startReadLoop, writeFrame, makeResult, makeError, JsonRpcError } from './utils.js';
import { listTools, callTool } from './handlers/tools.js';
import { listResources, readResource } from './handlers/resources.js';

// Validate config on startup (non-fatal: we still allow initialize/tools/list, but calls will fail)
const cfgErrors = validateConfig();
if (cfgErrors.length) {
  console.error('[startup] Configuration issues:', cfgErrors.join('; '));
}

function handleRequest(msg) {
  const { id, method, params } = msg;
  if (!method) {
    writeFrame(makeError(id ?? null, JsonRpcError.InvalidRequest, 'Missing method'));
    return;
  }

  switch (method) {
    case 'initialize':
      onInitialize(id, params).catch((e) => replyError(id, e, 'initialize'));
      break;
    case 'tools/list':
      onToolsList(id).catch((e) => replyError(id, e, 'tools/list'));
      break;
    case 'tools/call':
      onToolsCall(id, params).catch((e) => replyError(id, e, 'tools/call'));
      break;
    case 'resources/list':
      onResourcesList(id).catch((e) => replyError(id, e, 'resources/list'));
      break;
    case 'resources/read':
      onResourcesRead(id, params).catch((e) => replyError(id, e, 'resources/read'));
      break;
    default:
      writeFrame(makeError(id ?? null, JsonRpcError.MethodNotFound, `Method not found: ${method}`));
  }
}

async function onInitialize(id /*, params */) {
  const result = {
    serverInfo: { name: config.server.name, version: config.server.version },
    capabilities: { tools: {}, resources: {} },
  };
  writeFrame(makeResult(id, result));
}

async function onToolsList(id) {
  const result = await listTools();
  writeFrame(makeResult(id, result));
}

async function onToolsCall(id, params) {
  if (!params || typeof params.name !== 'string') {
    writeFrame(makeError(id, JsonRpcError.InvalidParams, 'Missing tool name'));
    return;
  }
  try {
    const res = await callTool(params.name, params.arguments || {});
    writeFrame(makeResult(id, res));
  } catch (e) {
    replyError(id, e, `tools/call:${params.name}`);
  }
}

async function onResourcesList(id) {
  const result = await listResources();
  writeFrame(makeResult(id, result));
}

async function onResourcesRead(id, params) {
  const uri = params?.uri;
  if (!uri) {
    writeFrame(makeError(id, JsonRpcError.InvalidParams, 'Missing uri'));
    return;
  }
  const result = await readResource(uri);
  writeFrame(makeResult(id, result));
}

function replyError(id, err, ctx) {
  const code = (err && err.code) || JsonRpcError.InternalError;
  const message = err?.message || 'Internal error';
  console.error(`[${ctx}] error:`, message, err?.stack || err);
  writeFrame(makeError(id ?? null, code, message));
}

// Start read loop
startReadLoop((msg) => {
  try {
    // Basic JSON-RPC validation
    if (!msg || msg.jsonrpc !== '2.0') {
      writeFrame(makeError(null, JsonRpcError.InvalidRequest, 'Invalid JSON-RPC version'));
      return;
    }
    if (msg.id === undefined) {
      // Notification; not used in this server but could be handled here
      // TODO: support notifications like ping if needed
      return;
    }
    handleRequest(msg);
  } catch (e) {
    console.error('[router] unexpected error:', e);
    writeFrame(makeError(msg?.id ?? null, JsonRpcError.InternalError, 'Unhandled exception'));
  }
});

// TODO: graceful shutdown on SIGINT/SIGTERM if needed
process.on('SIGINT', () => process.exit(0));
process.on('SIGTERM', () => process.exit(0));
