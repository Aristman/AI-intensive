// Utility helpers: JSON-RPC framing over STDIO and error helpers

// Write a JSON-RPC message to stdout with Content-Length framing
export function writeFrame(obj) {
  try {
    const payload = Buffer.from(JSON.stringify(obj), 'utf8');
    const header = `Content-Length: ${payload.length}\r\n\r\n`;
    process.stdout.write(header);
    process.stdout.write(payload);
  } catch (e) {
    console.error('[writeFrame] Failed to write frame:', e);
  }
}

// Read frames from stdin. Emits parsed JSON messages via onMessage callback.
export function startReadLoop(onMessage) {
  let buffer = Buffer.alloc(0);

  process.stdin.on('data', (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    try {
      // Parse as many frames as present in buffer
      while (true) {
        const headerEnd = buffer.indexOf('\r\n\r\n');
        if (headerEnd === -1) break; // need more data

        const headerBuf = buffer.subarray(0, headerEnd).toString('utf8');
        const match = /Content-Length:\s*(\d+)/i.exec(headerBuf);
        if (!match) {
          console.error('[startReadLoop] Missing Content-Length header');
          // drop until next CRLFCRLF
          buffer = buffer.subarray(headerEnd + 4);
          continue;
        }
        const contentLength = Number(match[1]);
        const totalLen = headerEnd + 4 + contentLength;
        if (buffer.length < totalLen) break; // wait for full body

        const body = buffer.subarray(headerEnd + 4, totalLen).toString('utf8');
        buffer = buffer.subarray(totalLen);

        let msg;
        try {
          msg = JSON.parse(body);
        } catch (e) {
          console.error('[startReadLoop] JSON parse error:', e);
          continue;
        }
        onMessage(msg);
      }
    } catch (e) {
      console.error('[startReadLoop] Unexpected parse error:', e);
    }
  });

  process.stdin.on('error', (e) => console.error('[stdin] error:', e));
}

// JSON-RPC helpers
export function makeResult(id, result) {
  return { jsonrpc: '2.0', id, result };
}

export function makeError(id, code, message, data) {
  return { jsonrpc: '2.0', id, error: { code, message, ...(data ? { data } : {}) } };
}

export const JsonRpcError = {
  ParseError: -32700,
  InvalidRequest: -32600,
  MethodNotFound: -32601,
  InvalidParams: -32602,
  InternalError: -32603,
  // -32000 to -32099: Server error (custom range)
  ServerError: -32000,
};

// Simple delay helper
export function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Retry helper with exponential backoff
// fn: async () => T
// options: { attempts=3, baseDelayMs=300, maxDelayMs=3000, shouldRetry?: (err|resp) => boolean }
export async function withRetries(fn, options = {}) {
  const attempts = Math.max(1, Number(options.attempts || 3));
  const base = Math.max(0, Number(options.baseDelayMs || 300));
  const maxDelay = Math.max(base, Number(options.maxDelayMs || 3000));
  const shouldRetry = options.shouldRetry || ((err) => {
    // Retry on AbortError, fetch/network errors, and HTTP 5xx if err.status present
    if (!err) return false;
    if (err.name === 'AbortError') return true;
    const code = err.status || err.code;
    if (typeof code === 'number' && code >= 500 && code < 600) return true;
    return false;
  });

  let lastError;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (e) {
      lastError = e;
      if (i === attempts - 1 || !shouldRetry(e)) break;
      const backoff = Math.min(maxDelay, base * Math.pow(2, i));
      console.error(`[withRetries] attempt ${i + 1} failed: ${e?.message || e}. Retrying in ${backoff}ms`);
      await delay(backoff);
    }
  }
  throw lastError;
}
