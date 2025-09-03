// ESM config for Yandex Search MCP Server
// Reads environment variables (supports .env via dotenv) and provides validated configuration.
import 'dotenv/config';

export const config = {
  server: {
    name: 'yandex_search_mcp',
    version: '0.1.0',
  },
  env: {
    apiKey: process.env.YANDEX_API_KEY || '',
    folderId: process.env.YANDEX_FOLDER_ID || '',
    baseUrl: process.env.YANDEX_SEARCH_BASE_URL || 'https://searchapi.api.cloud.yandex.net/v2/web/search',
    requestTimeoutMs: Number(process.env.REQUEST_TIMEOUT_MS || 15000),
    // HTTP mode toggle (REST instead of grpcurl). 'true' to enable
    useHttpMode: String(process.env.USE_HTTP_MODE || '').toLowerCase() === 'true',
    // gRPC settings
    iamToken: process.env.YANDEX_IAM_TOKEN || '',
    oauthToken: process.env.YANDEX_OAUTH_TOKEN || '',
    grpcEndpoint: process.env.YANDEX_SEARCH_GRPC_ENDPOINT || 'searchapi.api.cloud.yandex.net:443',
    grpcMethod: process.env.YANDEX_SEARCH_GRPC_METHOD || 'yandex.cloud.searchapi.v2.WebSearchService/Search',
    grpcurlPath: process.env.GRPCURL_PATH || 'D:/projects',
    _iamTokenExpiresAt: null, // ISO string or null
  },
};

export function validateConfig() {
  const errs = [];
  if (!config.env.folderId) errs.push('YANDEX_FOLDER_ID is required');
  if (errs.length) {
    // Log to stderr per requirements
    console.error('[config] Invalid configuration:', errs.join('; '));
  }
  return errs;
}

// Ensure we have a valid IAM token. If missing/expired and OAuth token is provided,
// exchange YANDEX_OAUTH_TOKEN -> YANDEX_IAM_TOKEN via Yandex IAM API.
export async function ensureIamToken() {
  const now = Date.now();
  // If we already have a non-expired IAM token, keep it
  if (config.env.iamToken && isTokenValid(config.env._iamTokenExpiresAt, now)) {
    return config.env.iamToken;
  }
  // If explicit IAM token provided but no expiry known, assume it's valid
  if (config.env.iamToken && !config.env.oauthToken) {
    return config.env.iamToken;
  }
  // Try to exchange via OAuth
  const oauth = config.env.oauthToken;
  if (!oauth) {
    // Nothing to do
    return config.env.iamToken;
  }
  try {
    console.error('[config.ensureIamToken] Exchanging OAuth -> IAM');
    const resp = await fetch('https://iam.api.cloud.yandex.net/iam/v1/tokens', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ yandexPassportOauthToken: oauth }),
    });
    if (!resp.ok) {
      const text = await safeText(resp);
      console.error('[config.ensureIamToken] Exchange failed', resp.status, text?.slice?.(0, 400));
      return config.env.iamToken; // fallback to existing value if any
    }
    const data = await resp.json();
    const iam = data.iamToken || data.token || '';
    const expiresAt = data.expiresAt || null;
    if (iam) {
      config.env.iamToken = iam;
      config.env._iamTokenExpiresAt = expiresAt;
      // Also reflect back to process.env for child consumers
      process.env.YANDEX_IAM_TOKEN = iam;
      console.error('[config.ensureIamToken] IAM token acquired; expiresAt=', expiresAt || 'unknown');
    }
    return config.env.iamToken;
  } catch (e) {
    console.error('[config.ensureIamToken] Error:', e?.message || e);
    return config.env.iamToken;
  }
}

function isTokenValid(expiresAt, nowMs) {
  if (!expiresAt) return false;
  try {
    const exp = Date.parse(expiresAt);
    if (Number.isNaN(exp)) return false;
    // Refresh 5 minutes before expiry
    return exp - nowMs > 5 * 60 * 1000;
  } catch {
    return false;
  }
}

async function safeText(resp) {
  try { return await resp.text(); } catch { return ''; }
}
