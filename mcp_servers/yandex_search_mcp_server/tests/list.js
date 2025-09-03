import { rpcOnce } from './runner.js';

rpcOnce({ method: 'tools/list', params: {} })
  .catch((e) => { console.error('tools/list test failed:', e); process.exit(1); });
