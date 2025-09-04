import { rpcOnce } from './runner.js';

const params = {
  clientInfo: { name: 'tests', version: '1.0' },
};

rpcOnce({ method: 'initialize', params })
  .catch((e) => { console.error('init test failed:', e); process.exit(1); });
