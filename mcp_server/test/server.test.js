import test from 'node:test';
import assert from 'node:assert/strict';

// Import utilities from server without starting the server (server.js auto-starts only when run directly)
import { RpcError, toJsonRpcError, jlog } from '../server.js';

test('RpcError basics', () => {
  const e = new RpcError(-32602, 'Invalid params', { x: 1 });
  assert.equal(e.code, -32602);
  assert.equal(e.message, 'Invalid params');
  assert.deepEqual(e.data, { x: 1 });
  assert.ok(e instanceof Error);
});

test('toJsonRpcError returns original code/message for RpcError', () => {
  const e = new RpcError(-32010, 'GitHub API error', { status: 500 });
  const r = toJsonRpcError(e);
  assert.equal(r.code, -32010);
  assert.equal(r.message, 'GitHub API error');
  assert.deepEqual(r.data, { status: 500 });
});

test('toJsonRpcError wraps generic Error as -32603 Internal error', () => {
  const r = toJsonRpcError(new Error('boom'));
  assert.equal(r.code, -32603);
  assert.equal(r.message, 'Internal error');
  assert.equal(r.data, 'boom');
});

test('jlog outputs valid JSON line with expected fields', () => {
  const orig = console.log;
  const lines = [];
  console.log = (s) => lines.push(s);
  try {
    jlog('info', 'custom_event', { a: 1 });
  } finally {
    console.log = orig;
  }
  assert.ok(lines.length >= 1);
  const last = lines[lines.length - 1];
  let obj;
  assert.doesNotThrow(() => { obj = JSON.parse(last); });
  assert.equal(obj.level, 'info');
  assert.equal(obj.event, 'custom_event');
  assert.equal(obj.a, 1);
  assert.ok(typeof obj.ts === 'string');
});
