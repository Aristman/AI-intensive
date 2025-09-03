// Tools handler: list and call tools
// All network operations are async. Errors/logs only to stderr.

import { config, ensureIamToken } from '../config.js';
import { withRetries } from '../utils.js';
import { spawn } from 'child_process';

// Describe available tools (MCP tools/list)
export async function listTools() {
  return {
    tools: [
      {
        name: 'yandex_search_web',
        description: 'Синхронный веб-поиск по Yandex Search API',
        inputSchema: {
          type: 'object',
          properties: {
            // Back-compat alias: если задано, будет скопировано в queryText
            query: { type: 'string', description: 'Поисковый запрос (alias к queryText)' },
            // Сообщение WebSearchRequest (часть полей)
            queryText: { type: 'string', description: 'Текст поискового запроса (<= 400 символов)' },
            searchType: { type: 'string', enum: ['SEARCH_TYPE_RU','SEARCH_TYPE_TR','SEARCH_TYPE_COM','SEARCH_TYPE_KK','SEARCH_TYPE_BE','SEARCH_TYPE_UZ'], default: 'SEARCH_TYPE_RU' },
            familyMode: { type: 'string', enum: ['FAMILY_MODE_MODERATE','FAMILY_MODE_NONE','FAMILY_MODE_STRICT'], default: 'FAMILY_MODE_MODERATE' },
            page: { type: 'integer', minimum: 0, default: 0, description: 'Номер страницы, с 0' },
            fixTypoMode: { type: 'string', enum: ['FIX_TYPO_MODE_ON','FIX_TYPO_MODE_OFF'], default: 'FIX_TYPO_MODE_ON' },
            sortMode: { type: 'string', enum: ['SORT_MODE_BY_RELEVANCE','SORT_MODE_BY_TIME'], default: 'SORT_MODE_BY_RELEVANCE' },
            sortOrder: { type: 'string', enum: ['SORT_ORDER_DESC','SORT_ORDER_ASC'], default: 'SORT_ORDER_DESC' },
            groupMode: { type: 'string', enum: ['GROUP_MODE_DEEP','GROUP_MODE_FLAT'], default: 'GROUP_MODE_FLAT' },
            groupsOnPage: { type: 'integer', description: 'HTML: 5–50; XML: 1–100', default: 10 },
            docsInGroup: { type: 'integer', minimum: 1, maximum: 3, default: 1 },
            maxPassages: { type: 'integer', minimum: 1, maximum: 5, default: 3 },
            region: { type: 'string', description: 'Идентификатор региона (строка)' },
            l10n: { type: 'string', enum: ['LOCALIZATION_RU','LOCALIZATION_BE','LOCALIZATION_KK','LOCALIZATION_UK','LOCALIZATION_TR','LOCALIZATION_EN'], default: 'LOCALIZATION_RU' },
            responseFormat: { type: 'string', enum: ['FORMAT_XML','FORMAT_HTML'], default: 'FORMAT_HTML' },
            userAgent: { type: 'string', description: 'Заголовок User-Agent' },
          },
          anyOf: [
            { required: ['queryText'] },
            { required: ['query'] },
          ],
          additionalProperties: false,
        },
      },
    ],
  };
}

function normalizeResultsFromXml(xml) {
  const out = [];
  if (!xml || typeof xml !== 'string') return out;
  try {
    // Very naive XML extraction without external deps
    const itemRe = /<item[\s\S]*?>[\s\S]*?<\/item>/gi;
    const urlRe = /<url>([\s\S]*?)<\/url>/i;
    const titleRe = /<title>([\s\S]*?)<\/title>/i;
    const linkRe = /<link>([\s\S]*?)<\/link>/i;
    const snippetRe = /<snippet>([\s\S]*?)<\/snippet>/i;
    const items = xml.match(itemRe) || [xml];
    for (const block of items) {
      const url = (block.match(urlRe)?.[1] || block.match(linkRe)?.[1] || '').trim();
      const title = collapseWhitespace(decodeEntities(stripTags((block.match(titleRe)?.[1] || '').toString())));
      const snippet = collapseWhitespace(decodeEntities(stripTags((block.match(snippetRe)?.[1] || '').toString())));
      if (isRealHttpUrl(url) && (title || snippet)) out.push({ title, url, snippet });
      if (out.length >= 10) break;
    }
  } catch (e) {
    console.error('[normalizeResultsFromXml] parse error:', e?.message || e);
  }
  return out;
}

// Call a tool by name (MCP tools/call)
export async function callTool(name, args = {}) {
  switch (name) {
    case 'yandex_search_web':
      return yandexSearchWeb(args);
    default:
      const err = `Tool not found: ${name}`;
      console.error('[tools.call] ', err);
      throw Object.assign(new Error(err), { code: -32601 }); // JSON-RPC Method not found
  }
}

async function yandexSearchWeb(args) {
  // Map input, preserving back-compat for 'query' -> 'queryText'
  const queryText = String((args.queryText ?? args.query ?? '')).trim();
  if (!queryText) {
    const msg = 'Invalid params: queryText (или query) должен быть непустой строкой';
    console.error('[yandex_search_web] ', msg);
    const e = new Error(msg);
    e.code = -32602;
    throw e;
  }

  // Compose WebSearchRequest JSON body
  const body = {
    query: {
      searchType: args.searchType || 'SEARCH_TYPE_RU',
      queryText,
      familyMode: args.familyMode || 'FAMILY_MODE_MODERATE',
      page: Number.isFinite(args.page) ? Math.max(0, Number(args.page)) : 0,
      fixTypoMode: args.fixTypoMode || 'FIX_TYPO_MODE_ON',
    },
    sortSpec: {
      sortMode: args.sortMode || 'SORT_MODE_BY_RELEVANCE',
      sortOrder: args.sortOrder || 'SORT_ORDER_DESC',
    },
    groupSpec: {
      groupMode: args.groupMode || 'GROUP_MODE_FLAT',
      groupsOnPage: Number.isFinite(args.groupsOnPage) ? Number(args.groupsOnPage) : 10,
      docsInGroup: Number.isFinite(args.docsInGroup) ? Number(args.docsInGroup) : 1,
    },
    maxPassages: Number.isFinite(args.maxPassages) ? Number(args.maxPassages) : 3,
    region: typeof args.region === 'string' ? args.region : (args.region != null ? String(args.region) : undefined),
    l10n: args.l10n || 'LOCALIZATION_RU',
    folderId: config.env.folderId,
    responseFormat: args.responseFormat || 'FORMAT_HTML',
    userAgent: args.userAgent || 'yandex-search-mcp/0.1.0',
  };

  // Remove undefined fields to keep payload clean
  pruneUndefined(body);

  // If HTTP mode enabled, call REST API; otherwise use grpcurl
  if (config.env.useHttpMode) {
    // Ensure we have credentials and folder
    if (!config.env.folderId) {
      const msg = 'Server config error: требуется YANDEX_FOLDER_ID для REST режима';
      console.error('[yandex_search_web][http] ', msg);
      const e = new Error(msg);
      e.code = -32000;
      throw e;
    }
    // If API key не указан, пробуем получить IAM токен из OAuth (или проверяем существующий)
    if (!config.env.apiKey) {
      await ensureIamToken();
      if (!config.env.iamToken) {
        const msg = 'Server config error: требуется один из: YANDEX_API_KEY или YANDEX_IAM_TOKEN (или YANDEX_OAUTH_TOKEN для обмена)';
        console.error('[yandex_search_web][http] ', msg);
        const e = new Error(msg);
        e.code = -32000;
        throw e;
      }
    }
    const httpResult = await withRetries(async () => {
      console.error('[yandex_search_web][http.request]', JSON.stringify({ url: config.env.baseUrl, headers: { Authorization: '***', 'x-folder-id': '[set]' }, body }));
      const { json } = await callHttpSearch(body, {
        timeoutMs: config.env.requestTimeoutMs,
      });
      return json;
    }, { attempts: 3, baseDelayMs: 400, maxDelayMs: 3000 });

    // Decode Base64 depending on requested format
    const respFormat = (body.responseFormat || 'FORMAT_HTML');
    let decoded = null;
    try {
      const b64 = httpResult?.rawData;
      if (typeof b64 === 'string' && b64.length > 0) {
        decoded = Buffer.from(b64, 'base64').toString('utf8');
      }
    } catch (e) {
      console.error('[yandex_search_web][decode_error]', e?.message || e);
    }

    const isXml = respFormat === 'FORMAT_XML';
    const textSummary = decoded
      ? `${isXml ? 'XML' : 'HTML'} decoded (truncated to 500 chars):\n` + truncate(decoded, 500)
      : 'No rawData in response';
    const normalized = isXml ? normalizeResultsFromXml(decoded) : normalizeResults(httpResult, decoded);
    return {
      content: [
        { type: 'text', text: textSummary },
        { type: 'json', json: { request: body, response: httpResult, decodedPreview: decoded ? truncate(decoded, 2000) : null, normalizedResults: normalized, responseFormat: respFormat } },
      ],
    };
  }

  // gRPC mode
  await ensureIamToken();
  if (!config.env.iamToken || !config.env.folderId) {
    const msg = 'Server config error: требуется YANDEX_FOLDER_ID и один из: YANDEX_IAM_TOKEN или YANDEX_OAUTH_TOKEN (для обмена на IAM)';
    console.error('[yandex_search_web] ', msg);
    const e = new Error(msg);
    e.code = -32000;
    throw e;
  }

  const grpcResult = await withRetries(async () => {
    console.error('[yandex_search_web][grpcurl.request]', JSON.stringify({ endpoint: config.env.grpcEndpoint, method: config.env.grpcMethod, headers: { Authorization: 'Bearer ***', 'x-folder-id': '[set]' }, body }));
    const { stdout } = await runGrpcurl(JSON.stringify(body), {
      token: config.env.iamToken,
      folderId: config.env.folderId,
      endpoint: config.env.grpcEndpoint,
      method: config.env.grpcMethod,
      timeoutMs: config.env.requestTimeoutMs,
    });
    let parsed;
    try {
      parsed = JSON.parse(stdout);
    } catch (e) {
      console.error('[yandex_search_web][grpcurl.parse_error]', e?.message || e);
      const err = new Error('Failed to parse JSON from grpcurl output');
      err.code = -32000;
      throw err;
    }
    return parsed;
  }, { attempts: 3, baseDelayMs: 400, maxDelayMs: 3000 });

  // Decode Base64 depending on requested format
  const respFormat = (body.responseFormat || 'FORMAT_HTML');
  let decoded = null;
  try {
    const b64 = grpcResult?.rawData;
    if (typeof b64 === 'string' && b64.length > 0) {
      decoded = Buffer.from(b64, 'base64').toString('utf8');
    }
  } catch (e) {
    console.error('[yandex_search_web][decode_error]', e?.message || e);
  }

  const isXml = respFormat === 'FORMAT_XML';
  const textSummary = decoded
    ? `${isXml ? 'XML' : 'HTML'} decoded (truncated to 500 chars):\n` + truncate(decoded, 500)
    : 'No rawData in response';
  const normalized = isXml ? normalizeResultsFromXml(decoded) : normalizeResults(grpcResult, decoded);
  return {
    content: [
      { type: 'text', text: textSummary },
      { type: 'json', json: { request: body, response: grpcResult, decodedPreview: decoded ? truncate(decoded, 2000) : null, normalizedResults: normalized, responseFormat: respFormat } },
    ],
  };
}

function runGrpcurl(jsonBody, opts) {
  const args = [];
  args.push('-H', `Authorization: Bearer ${opts.token}`);
  if (opts.folderId) args.push('-H', `x-folder-id: ${opts.folderId}`);
  args.push('-d', '@', '--', opts.endpoint, opts.method);

  return new Promise((resolve, reject) => {
    const child = spawn(config.env.grpcurlPath, args, { stdio: ['pipe', 'pipe', 'pipe'] });
    const timer = setTimeout(() => {
      try { child.kill('SIGKILL'); } catch {}
    }, Math.max(1000, Number(opts.timeoutMs || 15000)));

    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => { stdout += d.toString(); });
    child.stderr.on('data', (d) => { stderr += d.toString(); });
    child.on('error', (err) => {
      clearTimeout(timer);
      console.error('[yandex_search_web][grpcurl.error]', err?.message || err);
      const e = new Error('Failed to start grpcurl');
      e.code = -32000;
      reject(e);
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      if (stderr) console.error('[yandex_search_web][grpcurl.stderr]', truncate(stderr, 2000));
      if (code !== 0) {
        const e = new Error(`grpcurl exited with code ${code}`);
        e.code = -32000;
        return reject(e);
      }
      resolve({ stdout, stderr });
    });
    // write body via stdin
    try {
      child.stdin.write(jsonBody);
      child.stdin.end();
    } catch (e) {
      console.error('[yandex_search_web][grpcurl.stdin_error]', e?.message || e);
    }
  });
}

function pruneUndefined(obj) {
  for (const k of Object.keys(obj)) {
    const v = obj[k];
    if (v && typeof v === 'object' && !Array.isArray(v)) pruneUndefined(v);
    if (v === undefined) delete obj[k];
  }
}

function normalizeResults(data, decodedHtml) {
  // 1) Try any structured fields (future-proof if API adds them)
  const out = [];
  try {
    const docs = data?.results || data?.documents || data?.items || data?.groups || [];
    for (const d of docs) {
      const title = (d.title || d.name || d.caption || '').toString();
      const url = (d.url || d.link || d.href || '').toString();
      const snippet = (d.snippet || d.summary || d.text || '').toString();
      if ((title || url || snippet) && isRealHttpUrl(url)) out.push({ title, url, snippet });
    }
  } catch (e) {
    console.error('[normalizeResults] structured parse error:', e?.message || e);
  }

  // 2) Fallback: parse HTML from rawData (Yandex SERP HTML)
  if (decodedHtml && out.length < 3) {
    try {
      const results = extractFromHtml(decodedHtml);
      for (const r of results) {
        if (!out.find((x) => sameUrl(x.url, r.url))) out.push(r);
        if (out.length >= 10) break;
      }
    } catch (e) {
      console.error('[normalizeResults] html parse error:', e?.message || e);
    }
  }

  return out.slice(0, 10);
}

function extractFromHtml(html) {
  const res = [];
  const blacklist = [
    'yandex.ru', 'yastatic.net', 'yandex.net', 'yandex.com', 'yandex-team.ru',
  ];
  const anchorRe = /<a\b[^>]*href="(https?:\/\/[^"\s]+)"[^>]*>([\s\S]*?)<\/a>/gi;
  const seen = new Set();
  let m;
  while ((m = anchorRe.exec(html))) {
    const url = m[1];
    if (!isRealHttpUrl(url)) continue;
    if (blacklist.some((d) => url.includes(d))) continue;
    if (url.includes('/search?') || url.includes('clid=')) continue;
    const titleHtml = m[2] || '';
    const title = collapseWhitespace(decodeEntities(stripTags(titleHtml))).trim();
    if (!title) continue;
    if (seen.has(url)) continue;

    // Capture a snippet from the following text window
    const afterIdx = m.index + m[0].length;
    const windowText = collapseWhitespace(
      decodeEntities(
        stripTags(html.slice(afterIdx, afterIdx + 800))
      )
    );
    const snippet = trimToSentence(windowText, 220);

    seen.add(url);
    res.push({ title, url, snippet });
    if (res.length >= 10) break;
  }
  return res;
}

function stripTags(s) {
  if (!s) return '';
  return s
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ');
}

function decodeEntities(s) {
  if (!s) return '';
  return s
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'");
}

function collapseWhitespace(s) {
  return (s || '').replace(/\s+/g, ' ').trim();
}

function trimToSentence(s, maxLen) {
  const t = (s || '').slice(0, maxLen * 2);
  const dot = t.indexOf('. ');
  const cut = dot > 40 ? dot + 1 : maxLen; // prefer early sentence end
  return collapseWhitespace(t.slice(0, cut)).slice(0, maxLen);
}

function isRealHttpUrl(u) {
  if (!u || typeof u !== 'string') return false;
  if (!/^https?:\/\//i.test(u)) return false;
  try { new URL(u); return true; } catch { return false; }
}

function sameUrl(a, b) {
  try {
    const ua = new URL(a);
    const ub = new URL(b);
    return ua.href.replace(/[#?].*$/, '') === ub.href.replace(/[#?].*$/, '');
  } catch { return a === b; }
}

async function safeText(resp) {
  try {
    return await resp.text();
  } catch {
    return '';
  }
}

function truncate(s, n) {
  if (!s) return s;
  return s.length > n ? s.slice(0, n) + '…' : s;
}

// REST helper: POST search request with timeout and proper headers
async function callHttpSearch(body, { timeoutMs = 15000 } = {}) {
  const url = config.env.baseUrl;
  const headers = {
    'content-type': 'application/json',
  };
  if (config.env.folderId) headers['x-folder-id'] = config.env.folderId;

  // Prefer Api-Key if provided; otherwise Bearer IAM
  if (config.env.apiKey) {
    headers['Authorization'] = `Api-Key ${config.env.apiKey}`;
  } else if (config.env.iamToken) {
    headers['Authorization'] = `Bearer ${config.env.iamToken}`;
  }

  const controller = new AbortController();
  const to = setTimeout(() => controller.abort(), Math.max(1000, Number(timeoutMs || 15000)));
  try {
    const resp = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    const text = await safeText(resp);
    let json = null;
    try { json = text ? JSON.parse(text) : null; } catch {}
    if (!resp.ok) {
      const err = new Error(`HTTP ${resp.status}: ${truncate(text || '', 500)}`);
      err.code = -32000;
      throw err;
    }
    if (!json) {
      const err = new Error('Empty or invalid JSON response from REST API');
      err.code = -32000;
      throw err;
    }
    return { json, status: resp.status };
  } finally {
    clearTimeout(to);
  }
}
