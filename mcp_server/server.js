import 'dotenv/config';
import { WebSocketServer } from 'ws';
import axios from 'axios';
import { exec as _exec } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, writeFile, rm, mkdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

const PORT = process.env.PORT ? Number(process.env.PORT) : 3001;
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const TELEGRAM_DEFAULT_CHAT_ID = process.env.TELEGRAM_DEFAULT_CHAT_ID;

const execAsync = promisify(_exec);

async function createTempDir(prefix = 'mcp-java-') {
  const dir = await mkdtemp(path.join(os.tmpdir(), prefix));
  return dir;
}

async function writeFilesToDir(baseDir, files) {
  // files: Array<{ path: string, content: string }>
  for (const f of files) {
    const abs = path.join(baseDir, f.path);
    await mkdir(path.dirname(abs), { recursive: true });
    await writeFile(abs, f.content, 'utf8');
  }
}

async function downloadToFile(url, destAbsPath) {
  const resp = await axios.get(url, { responseType: 'arraybuffer' });
  await mkdir(path.dirname(destAbsPath), { recursive: true });
  await writeFile(destAbsPath, resp.data);
}

function detectPackageFqcn(javaFilePath, javaContent) {
  // Derive FQCN from optional package declaration + filename
  const base = path.basename(javaFilePath).replace(/\.java$/i, '');
  const m = /\bpackage\s+([a-zA-Z0-9_.]+)\s*;/m.exec(javaContent || '');
  return m ? `${m[1]}.${base}` : base;
}

if (!GITHUB_TOKEN) {
  console.warn('[MCP] Warning: GITHUB_TOKEN is not set. create_issue and private repos will fail.');
}
if (!TELEGRAM_BOT_TOKEN) {
  console.warn('[MCP] Warning: TELEGRAM_BOT_TOKEN is not set. Telegram tools will fail.');
}

const wss = new WebSocketServer({ port: PORT });
console.log(`[MCP] Server started on ws://localhost:${PORT}`);

function send(ws, msg) {
  ws.send(JSON.stringify(msg));
}

function makeError(id, code, message, data) {
  return { jsonrpc: '2.0', id, error: { code, message, data } };
}

function makeResult(id, result) {
  return { jsonrpc: '2.0', id, result };
}

async function ghRequest(method, url, body) {
  const base = 'https://api.github.com';
  const headers = {
    Accept: 'application/vnd.github.v3+json',
    ...(GITHUB_TOKEN ? { Authorization: `token ${GITHUB_TOKEN}` } : {}),
  };
  const resp = await axios({ method, url: base + url, data: body, headers });
  return resp.data;
}

async function tgRequest(methodName, payload) {
  if (!TELEGRAM_BOT_TOKEN) throw new Error('TELEGRAM_BOT_TOKEN is not configured on server');
  const url = `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/${methodName}`;
  const resp = await axios.post(url, payload);
  const data = resp.data;
  if (data && data.ok === false) {
    throw new Error(`Telegram API error: ${JSON.stringify(data)}`);
  }
  return data?.result ?? data;
}

async function handleToolCall(name, args) {
  switch (name) {
    case 'get_repo': {
      const { owner, repo } = args || {};
      if (!owner || !repo) throw new Error('owner and repo are required');
      return await ghRequest('GET', `/repos/${owner}/${repo}`);
    }
    case 'search_repos': {
      const { query } = args || {};
      if (!query) throw new Error('query is required');
      const data = await ghRequest('GET', `/search/repositories?q=${encodeURIComponent(query)}`);
      return data.items || [];
    }
    case 'create_issue': {
      if (!GITHUB_TOKEN) throw new Error('GITHUB_TOKEN is not configured on server');
      const { owner, repo, title, body } = args || {};
      if (!owner || !repo || !title) throw new Error('owner, repo, title are required');
      return await ghRequest('POST', `/repos/${owner}/${repo}/issues`, { title, body });
    }
    case 'list_issues': {
      const { owner, repo, state = 'open', per_page = 5, page = 1 } = args || {};
      if (!owner || !repo) throw new Error('owner and repo are required');
      const qs = new URLSearchParams({ state: String(state), per_page: String(per_page), page: String(page) }).toString();
      const items = await ghRequest('GET', `/repos/${owner}/${repo}/issues?${qs}`);
      // Filter out PRs
      const issuesOnly = Array.isArray(items) ? items.filter((it) => !it.pull_request) : [];
      return issuesOnly;
    }
    case 'tg_send_message': {
      const { chat_id, text, parse_mode, disable_web_page_preview } = args || {};
      if (!text) throw new Error('text is required');
      const cid = chat_id ?? TELEGRAM_DEFAULT_CHAT_ID;
      if (!cid) throw new Error('chat_id is required (or set TELEGRAM_DEFAULT_CHAT_ID)');
      return await tgRequest('sendMessage', { chat_id: cid, text, parse_mode, disable_web_page_preview });
    }
    case 'tg_send_photo': {
      const { chat_id, photo, caption, parse_mode } = args || {};
      if (!photo) throw new Error('photo (URL or file_id) is required');
      const cid = chat_id ?? TELEGRAM_DEFAULT_CHAT_ID;
      if (!cid) throw new Error('chat_id is required (or set TELEGRAM_DEFAULT_CHAT_ID)');
      return await tgRequest('sendPhoto', { chat_id: cid, photo, caption, parse_mode });
    }
    case 'tg_get_updates': {
      const { offset, timeout, allowed_updates } = args || {};
      return await tgRequest('getUpdates', { offset, timeout, allowed_updates });
    }
    case 'create_issue_and_notify': {
      if (!GITHUB_TOKEN) throw new Error('GITHUB_TOKEN is not configured on server');
      const { owner, repo, title, body, chat_id, message_template } = args || {};
      if (!owner || !repo || !title) throw new Error('owner, repo, title are required');
      const issue = await ghRequest('POST', `/repos/${owner}/${repo}/issues`, { title, body });
      const cid = chat_id ?? TELEGRAM_DEFAULT_CHAT_ID;
      if (!cid) throw new Error('chat_id is required (or set TELEGRAM_DEFAULT_CHAT_ID)');
      const issueUrl = issue?.html_url || issue?.url || '';
      const defaultMsg = `New GitHub issue created: ${owner}/${repo}\n#${issue?.number ?? ''} ${title}\n${issueUrl}`;
      const text = message_template || defaultMsg;
      await tgRequest('sendMessage', { chat_id: cid, text });
      return { issue, notified: true };
    }
    case 'docker_start_java': {
      const {
        container_name = 'java-dev',
        image = 'eclipse-temurin:20-jdk',
        port = 8080,
        extra_args = '',
      } = args || {};

      // 1) Check if container exists
      const existsCmd = `docker ps -a --filter name=^/${container_name}$ --format {{.ID}}`;
      const { stdout: existsOut } = await execAsync(existsCmd).catch((e) => ({ stdout: '', stderr: String(e) }));
      const exists = Boolean((existsOut || '').trim());

      if (exists) {
        // 2) Try to start if not running
        const statusCmd = `docker ps --filter name=^/${container_name}$ --format {{.Status}}`;
        const { stdout: statusOut } = await execAsync(statusCmd).catch(() => ({ stdout: '' }));
        const isUp = Boolean((statusOut || '').trim());
        if (!isUp) {
          await execAsync(`docker start ${container_name}`);
        }
        return { container: container_name, image, state: 'running', existed: true };
      }

      // 3) Pull image and run new container
      await execAsync(`docker pull ${image}`);
      const runCmd = `docker run -d --name ${container_name} --restart unless-stopped -p ${port}:8080 ${extra_args} ${image} tail -f /dev/null`;
      const { stdout: runOut } = await execAsync(runCmd);
      return { container: container_name, image, state: 'running', id: (runOut || '').trim(), existed: false };
    }
    case 'docker_exec_java': {
      const startAll = Date.now();
      const {
        // Source inputs
        filename,
        code,
        files,
        // Execution config
        entrypoint,
        classpath,
        compile_args = [],
        run_args = [],
        // Docker config
        image = 'eclipse-temurin:20-jdk',
        container_name,
        extra_args = '',
        workdir = '/work',
        // Controls
        timeout_ms = 15000,
        limits = {}, // { cpus?: number, memory?: string }
        cleanup = 'always', // 'always' | 'on_success' | 'never'
      } = args || {};

      // Validate inputs
      let fileList = [];
      if (Array.isArray(files) && files.length > 0) {
        fileList = files.map((f) => ({ path: String(f.path), content: String(f.content ?? '') }));
      } else {
        if (!filename || typeof code !== 'string') {
          throw new Error("Either 'files' or both 'filename' and 'code' are required");
        }
        fileList = [{ path: String(filename), content: String(code) }];
      }

      // Try to detect if tests with JUnit4 are present
      const javaFilesWithContent = fileList.filter((f) => /\.java$/i.test(f.path));
      const junit4Detected = javaFilesWithContent.some((f) => {
        const c = String(f.content || '');
        return c.includes('import org.junit') || /@Test\b/.test(c);
      });

      // Detect a plausible entrypoint (FQCN). Prefer a test class if JUnit4 detected.
      let detectedFqcn = null;
      if (!entrypoint) {
        let candidate = javaFilesWithContent.find((f) => /Test\.java$/i.test(f.path)) || javaFilesWithContent[0] || fileList[0];
        if (candidate) {
          detectedFqcn = detectPackageFqcn(candidate.path, String(candidate.content || ''));
        }
      }
      const mainClass = entrypoint || detectedFqcn || path.basename(fileList[0].path).replace(/\.java$/i, '');

      // Prepare temp dir and write files
      const hostDir = await createTempDir();
      await writeFilesToDir(hostDir, fileList);

      const relJavaFiles = fileList
        .map((f) => f.path)
        .filter((p) => p.toLowerCase().endsWith('.java'));
      if (relJavaFiles.length === 0) {
        // No explicit java files: compile everything under dir
        relJavaFiles.push(fileList[0].path);
      }

      const { cpus = 1, memory = '512m' } = limits || {};
      const dockerBase = `docker run --rm ${container_name ? `--name ${container_name}` : ''} --cpus=${cpus} --memory=${memory} -v "${hostDir}":${workdir} -w ${workdir} ${extra_args} ${image}`;

      // Prepare JUnit4 libs if needed
      let junitCpRel = '';
      if (junit4Detected) {
        try {
          const libDir = path.join(hostDir, 'lib');
          const junitJar = path.join(libDir, 'junit-4.13.2.jar');
          const hamcrestJar = path.join(libDir, 'hamcrest-core-1.3.jar');
          await downloadToFile('https://repo1.maven.org/maven2/junit/junit/4.13.2/junit-4.13.2.jar', junitJar);
          await downloadToFile('https://repo1.maven.org/maven2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar', hamcrestJar);
          // Inside container we address them via volume-mounted relative path
          junitCpRel = `lib/junit-4.13.2.jar:lib/hamcrest-core-1.3.jar`;
        } catch (e) {
          // If download fails, continue without JUnit (will likely fail to compile)
          junitCpRel = '';
        }
      }

      // Build compile classpath
      let compileCp = '';
      const cpParts = [];
      if (classpath) cpParts.push(String(classpath));
      if (junitCpRel) cpParts.push(junitCpRel);
      if (cpParts.length > 0) {
        compileCp = `-cp '${cpParts.join(':')}'`;
      }
      const compileArgsStr = Array.isArray(compile_args) ? compile_args.map((a) => `'${String(a)}'`).join(' ') : '';
      const filesStr = relJavaFiles.map((p) => `'${p}'`).join(' ');
      const compileCmd = `${dockerBase} sh -lc "javac -d . ${compileCp} ${compileArgsStr} ${filesStr}"`;

      let compile = { stdout: '', stderr: '', exitCode: 0, durationMs: 0 };
      try {
        const t0 = Date.now();
        const { stdout, stderr } = await execAsync(compileCmd, { timeout: timeout_ms, maxBuffer: 10 * 1024 * 1024 });
        compile = { stdout, stderr, exitCode: 0, durationMs: Date.now() - t0 };
      } catch (e) {
        compile = {
          stdout: e.stdout ?? '',
          stderr: e.stderr ?? String(e.message ?? e),
          exitCode: Number.isInteger(e.code) ? e.code : 1,
          durationMs: Date.now() - startAll,
        };
        // Decide cleanup
        const shouldCleanup = cleanup === 'always' || (cleanup === 'on_success' ? false : false);
        if (shouldCleanup) {
          await rm(hostDir, { recursive: true, force: true }).catch(() => {});
        }
        return {
          image,
          limits: { cpus, memory },
          timeoutMs: timeout_ms,
          workdirHost: hostDir,
          workdirContainer: workdir,
          files: fileList.map((f) => f.path),
          compile,
          success: false,
        };
      }

      // Build run classpath
      const runCpParts = [`.`, ...(classpath ? [String(classpath)] : []), ...(junitCpRel ? [junitCpRel] : [])];
      const runCp = `-cp '${runCpParts.join(':')}'`;
      const runArgsStr = Array.isArray(run_args) ? run_args.map((a) => `'${String(a)}'`).join(' ') : '';
      // If JUnit4 detected, run via JUnitCore; otherwise run main class
      const runMain = junit4Detected ? `org.junit.runner.JUnitCore '${mainClass}'` : `'${mainClass}'`;
      const runCmd = `${dockerBase} sh -lc "java ${runCp} ${runMain} ${runArgsStr}"`;

      let run = { stdout: '', stderr: '', exitCode: 0, durationMs: 0 };
      try {
        const t1 = Date.now();
        const { stdout, stderr } = await execAsync(runCmd, { timeout: timeout_ms, maxBuffer: 10 * 1024 * 1024 });
        run = { stdout, stderr, exitCode: 0, durationMs: Date.now() - t1 };
      } catch (e) {
        run = {
          stdout: e.stdout ?? '',
          stderr: e.stderr ?? String(e.message ?? e),
          exitCode: Number.isInteger(e.code) ? e.code : 1,
          durationMs: Date.now() - startAll - compile.durationMs,
        };
      }

      const totalDuration = Date.now() - startAll;
      const success = run.exitCode === 0;
      const shouldCleanup = cleanup === 'always' || (cleanup === 'on_success' ? success : false);
      if (shouldCleanup) {
        await rm(hostDir, { recursive: true, force: true }).catch(() => {});
      }

      return {
        image,
        limits: { cpus, memory },
        timeoutMs: timeout_ms,
        workdirHost: hostDir,
        workdirContainer: workdir,
        files: fileList.map((f) => f.path),
        compile,
        run,
        durationMs: totalDuration,
        success,
      };
    }
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

wss.on('connection', (ws) => {
  ws.on('message', async (raw) => {
    let msg;
    try { msg = JSON.parse(raw.toString()); } catch {
      return send(ws, makeError(null, -32700, 'Parse error'));
    }

    const { id, method, params } = msg;
    if (!method) {
      return send(ws, makeError(id ?? null, -32600, 'Invalid Request'));
    }

    try {
      if (method === 'initialize') {
        return send(ws, makeResult(id, {
          serverInfo: { name: 'mcp-github-telegram-server', version: '1.1.0' },
          capabilities: { tools: true },
        }));
      }
      if (method === 'tools/list') {
        return send(ws, makeResult(id, {
          tools: [
            { name: 'get_repo', description: 'Get GitHub repo info', inputSchema: { owner: 'string', repo: 'string' } },
            { name: 'search_repos', description: 'Search GitHub repos', inputSchema: { query: 'string' } },
            { name: 'create_issue', description: 'Create GitHub issue', inputSchema: { owner: 'string', repo: 'string', title: 'string', body: 'string?' } },
            { name: 'list_issues', description: 'List issues for a repo (no PRs)', inputSchema: { owner: 'string', repo: 'string', state: 'string?', per_page: 'number?', page: 'number?' } },
            { name: 'tg_send_message', description: 'Send Telegram text message', inputSchema: { chat_id: 'string?', text: 'string', parse_mode: 'string?', disable_web_page_preview: 'boolean?' } },
            { name: 'tg_send_photo', description: 'Send Telegram photo by URL or file_id', inputSchema: { chat_id: 'string?', photo: 'string', caption: 'string?', parse_mode: 'string?' } },
            { name: 'tg_get_updates', description: 'Get Telegram updates (long polling)', inputSchema: { offset: 'number?', timeout: 'number?', allowed_updates: 'string[]?' } },
            { name: 'create_issue_and_notify', description: 'Create GitHub issue and notify Telegram chat', inputSchema: { owner: 'string', repo: 'string', title: 'string', body: 'string?', chat_id: 'string?', message_template: 'string?' } },
            { name: 'docker_start_java', description: 'Start (or create and start) a local Docker container with Java JDK', inputSchema: { container_name: 'string?', image: 'string?', port: 'number?', extra_args: 'string?' } },
            { name: 'docker_exec_java', description: 'Compile and run Java code inside a Docker container (volume-mounted workspace)', inputSchema: { filename: 'string?', code: 'string?', files: 'Array<{path:string,content:string}>?', entrypoint: 'string?', classpath: 'string?', compile_args: 'string[]?', run_args: 'string[]?', image: 'string?', container_name: 'string?', extra_args: 'string?', workdir: 'string?', timeout_ms: 'number?', limits: '{cpus?:number,memory?:string}?', cleanup: "'always'|'on_success'|'never'?" } },
          ],
        }));
      }
      if (method === 'tools/call') {
        const { name, arguments: args } = params || {};
        const result = await handleToolCall(name, args);
        return send(ws, makeResult(id, { name, result }));
      }

      return send(ws, makeError(id, -32601, 'Method not found'));
    } catch (err) {
      const message = err?.response?.data || err?.message || String(err);
      return send(ws, makeError(id, -32000, 'Tool call failed', message));
    }
  });
});
