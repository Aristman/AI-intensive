// Test runner utilities for STDIO MCP server
// Spawns the server, sends a single JSON-RPC request (with Content-Length framing),
// waits for the first response frame, prints it to stdout, and exits.

import { spawn } from 'node:child_process';

function buildFrame(obj) {
  const json = JSON.stringify(obj);
  const len = Buffer.byteLength(json, 'utf8');
  return `Content-Length: ${len}\r\n\r\n${json}`;
}

function parseFrames(buffer) {
  const frames = [];
  let buf = buffer;
  while (true) {
    const headerEnd = buf.indexOf('\r\n\r\n');
    if (headerEnd === -1) break;
    const header = buf.slice(0, headerEnd).toString('utf8');
    const m = /Content-Length:\s*(\d+)/i.exec(header);
    if (!m) {
      // drop invalid header
      buf = buf.slice(headerEnd + 4);
      continue;
    }
    const contentLength = Number(m[1]);
    const totalLen = headerEnd + 4 + contentLength;
    if (buf.length < totalLen) break;
    const body = buf.slice(headerEnd + 4, totalLen).toString('utf8');
    frames.push(body);
    buf = buf.slice(totalLen);
  }
  return { frames, rest: buf };
}

export async function rpcOnce({ method, params, cwd = process.cwd() }) {
  return new Promise((resolve, reject) => {
    // Use the same Node binary running this script for portability
    const child = spawn(process.execPath, ['./src/index.js'], { cwd });

    let outBuf = Buffer.alloc(0);
    let errBuf = '';
    let resolved = false;

    child.stdout.on('data', (chunk) => {
      outBuf = Buffer.concat([outBuf, chunk]);
      const { frames } = parseFrames(outBuf.toString('utf8'));
      if (frames.length > 0) {
        // Print the first frame
        console.log(`Content-Length: ${Buffer.byteLength(frames[0], 'utf8')}\n\n${frames[0]}`);
        // Give stderr a moment to flush, then print it and exit
        if (!resolved) {
          resolved = true;
          setTimeout(() => {
            if (errBuf) {
              console.error(errBuf);
            }
            try { child.kill(); } catch {}
            resolve(frames[0]);
          }, 150);
        }
      }
    });

    child.stderr.on('data', (chunk) => {
      errBuf += chunk.toString('utf8');
    });

    child.on('error', (e) => reject(e));
    child.on('close', (code) => {
      if (code !== 0 && !outBuf.length) {
        if (errBuf) {
          console.error(errBuf);
        }
        return reject(new Error(`Server exited with code ${code}. Stderr above.`));
      }
    });

    const frame = buildFrame({ jsonrpc: '2.0', id: '1', method, params: params || {} });
    child.stdin.write(frame);
    // Close stdin to signal no more messages in this test
    child.stdin.end();
  });
}

// If run directly: node tests/runner.js <method> <paramsJson>
if (import.meta.url === `file://${process.argv[1]}`) {
  const method = process.argv[2];
  const paramsJson = process.argv[3] || '{}';
  if (!method) {
    console.error('Usage: node tests/runner.js <method> <paramsJson>');
    process.exit(2);
  }
  let params;
  try { params = JSON.parse(paramsJson); } catch (e) {
    console.error('Invalid params JSON:', e.message);
    process.exit(2);
  }
  rpcOnce({ method, params, cwd: process.cwd() }).catch((e) => {
    console.error('Test run failed:', e);
    process.exit(1);
  });
}
