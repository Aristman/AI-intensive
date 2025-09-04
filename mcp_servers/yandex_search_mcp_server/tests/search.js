import { rpcOnce } from './runner.js';

// Provide a safe default query; requires valid API credentials in .env
const args = {
  name: 'yandex_search_web',
  arguments: {
    query: 'site:yandex.ru test',
    page: 1,
    pageSize: 3
  }
};

rpcOnce({ method: 'tools/call', params: args })
  .catch((e) => { console.error('tools/call test failed:', e); process.exit(1); });
