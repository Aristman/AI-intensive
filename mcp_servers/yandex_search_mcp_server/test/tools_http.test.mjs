// mcp_servers/yandex_search_mcp_server/test/tools_http.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';

// Импортируем один раз и далее меняем config.env между тестами
import { callTool } from '../src/handlers/tools.js';
import { config } from '../src/config.js';

// 1) Базовый успешный сценарий через Api-Key
test('REST: success via Api-Key', async () => {
  // Настроим конфиг для REST
  config.env.useHttpMode = true;
  config.env.baseUrl = 'https://searchapi.api.cloud.yandex.net/v2/web/search';
  config.env.folderId = 'test-folder';
  config.env.apiKey = 'test-api-key';
  config.env.iamToken = '';
  config.env.requestTimeoutMs = 5000;

  // Мокаем fetch
  global.fetch = async (url, init) => {
    assert.equal(url, config.env.baseUrl);
    assert.equal(init.method, 'POST');
    assert.ok(init.headers['content-type'].includes('application/json'));
    assert.equal(init.headers['x-folder-id'], 'test-folder');
    assert.equal(init.headers['Authorization'], `Api-Key ${config.env.apiKey}`);

    const parsed = JSON.parse(init.body);
    assert.equal(parsed.query.queryText, 'hello world');

    const raw = Buffer.from('<html><body><a href="https://example.com">Example</a></body></html>').toString('base64');
    const body = JSON.stringify({ rawData: raw });
    return new Response(body, { status: 200, headers: { 'content-type': 'application/json' } });
  };

  const res = await callTool('yandex_search_web', {
    queryText: 'hello world',
    responseFormat: 'FORMAT_HTML',
  });

  assert.ok(Array.isArray(res.content));
  const jsonPart = res.content.find(x => x.type === 'json');
  assert.ok(jsonPart, 'json part present');
  assert.ok(jsonPart.json.response.rawData, 'rawData present');
  assert.ok(jsonPart.json.decodedPreview?.includes('example.com'), 'decoded contains URL');
});

// 2) Fallback на Bearer, если Api-Key не задан
test('REST: falls back to Bearer when no Api-Key', async () => {
  config.env.useHttpMode = true;
  config.env.baseUrl = 'https://searchapi.api.cloud.yandex.net/v2/web/search';
  config.env.folderId = 'test-folder';
  config.env.apiKey = '';
  config.env.iamToken = 'iam-token-here';

  global.fetch = async (_url, init) => {
    assert.equal(init.headers['Authorization'], `Bearer ${config.env.iamToken}`);
    const body = JSON.stringify({ rawData: Buffer.from('<html></html>').toString('base64') });
    return new Response(body, { status: 200, headers: { 'content-type': 'application/json' } });
  };

  const res = await callTool('yandex_search_web', { queryText: 'hello bearer' });
  assert.ok(res.content.find(x => x.type === 'json'));
});

// 3) Ошибка при отсутствии folderId
test('REST: missing folderId -> config error', async () => {
  config.env.useHttpMode = true;
  config.env.baseUrl = 'https://searchapi.api.cloud.yandex.net/v2/web/search';
  config.env.folderId = '';
  config.env.apiKey = 'test-api-key';
  config.env.iamToken = '';

  let fetchCalled = false;
  global.fetch = async () => {
    fetchCalled = true;
    return new Response('{}', { status: 200, headers: { 'content-type': 'application/json' } });
  };

  await assert.rejects(
    () => callTool('yandex_search_web', { queryText: 'no folder' }),
    (e) => {
      assert.equal(e.code, -32000);
      return true;
    }
  );
  assert.equal(fetchCalled, false, 'fetch must not be called');
});
