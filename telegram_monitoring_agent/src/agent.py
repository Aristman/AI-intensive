#!/usr/bin/env python3
"""
Telegram Monitoring Agent Core
"""

import asyncio
import json
import logging
import os
from typing import Optional, Dict, Any
from .mcp_client import MCPClient
from .ui import TelegramUI
from .yandexgpt_usecase import YandexGptUseCase
from datetime import datetime, timedelta, time as dtime

class TelegramAgent:
    def __init__(self, config_path: str = "config/config.json"):
        # Load base config
        self.config = self.load_config(config_path)
        # Load .env from project directory and apply overrides
        self._load_env_file()
        self._apply_env_overrides()

        # Initialize MCP client with transport configuration
        mcp_command = self.config.get("mcp_server_command", "telegram-mcp")
        mcp_env_vars = self.config.get("mcp_env_vars", {})
        mcp_transport = self.config.get("mcp_transport", "stdio")
        mcp_ssh_config = self.config.get("mcp_ssh_tunnel", {})
        mcp_http_config = self.config.get("mcp_http_remote", {})

        self.mcp_client = MCPClient(
            command=mcp_command,
            env_vars=mcp_env_vars,
            transport=mcp_transport,
            ssh_config=mcp_ssh_config,
            http_config=mcp_http_config
        )

        self.ui = TelegramUI(self)
        self.mcp_transport = mcp_transport
        # Track last seen message id per chat for "new messages" logging
        self.last_seen_ids: Dict[str, int] = {}
        # Target chat to post summaries; fallback to source chat if not set
        self.summary_chat: Optional[str] = self.config.get('summary_chat')
        # Monitoring parameters from config
        self.monitor_interval_sec: int = int(self.config.get('monitor_interval_sec', 60))
        self.page_size: int = int(self.config.get('page_size', 10))
        self.chunk_size: int = int(self.config.get('chunk_size', 12))
        # State file for last_seen_ids
        self.state_file: str = 'logs/last_seen.json'
        # Optional schedule settings
        self.monitor_report_times = self.config.get('monitor_report_times') or []
        # Filtering/reporting behavior
        self.filter_mode: str = str(self.config.get('filter_mode', 'strict')).lower()
        self.report_if_empty: bool = bool(self.config.get('report_if_empty', False))
        # Concurrency guard to avoid overlapping monitoring runs
        self._monitor_lock: asyncio.Lock = asyncio.Lock()

        # Setup logging
        self.setup_logging()
        self.logger = logging.getLogger('TelegramAgent')
        self.logger.info(f"Telegram Monitoring Agent initialized with {mcp_transport} transport")

        # Load persisted last_seen_ids
        self._load_last_seen()

        # No direct Telegram connection: only MCP stdio transport is used
        
    def load_config(self, path: str) -> Dict[str, Any]:
        try:
            with open(path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            # Log explicit warning to avoid silent fallback
            try:
                logging.getLogger('TelegramAgent').warning(f"Failed to load config from '{path}': {e}. Falling back to default_config().")
            except Exception:
                pass
            return self.default_config()

    def _env_path(self) -> str:
        """Resolve absolute path to telegram_monitoring_agent/.env"""
        try:
            base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))
            return os.path.join(base_dir, '.env')
        except Exception:
            return '.env'

    def _load_env_file(self):
        """Load environment variables from telegram_monitoring_agent/.env.

        Tries python-dotenv if available; otherwise, performs minimal parsing of KEY=VALUE lines.
        """
        env_file = self._env_path()
        try:
            # Try python-dotenv first
            try:
                from dotenv import load_dotenv  # type: ignore
                load_dotenv(env_file)
                return
            except Exception:
                pass

            # Fallback: simple parser
            if os.path.exists(env_file):
                with open(env_file, 'r', encoding='utf-8') as f:
                    for line in f:
                        s = line.strip()
                        if not s or s.startswith('#'):
                            continue
                        if '=' in s:
                            k, v = s.split('=', 1)
                            k = k.strip()
                            v = v.strip().strip('"').strip("'")
                            # Do not override already set env
                            if k and (k not in os.environ):
                                os.environ[k] = v
        except Exception as e:
            try:
                logging.getLogger('TelegramAgent').warning(f"Failed to load .env: {e}")
            except Exception:
                pass

    def _apply_env_overrides(self):
        """Override critical config values from environment variables."""
        env = os.environ

        def _ovr(cfg_key: str, env_key: str, cast=None, path: Optional[list] = None):
            val = env.get(env_key)
            if val is None or str(val).strip() == '':
                return
            try:
                dst = self.config
                if path:
                    for p in path:
                        if p not in dst or not isinstance(dst[p], dict):
                            dst[p] = {}
                        dst = dst[p]
                    key = cfg_key
                    dst[key] = cast(val) if cast else val
                else:
                    self.config[cfg_key] = cast(val) if cast else val
            except Exception:
                self.config[cfg_key] = val

        # No Telegram direct creds or LLM secrets here; kept only in secure envs of respective services

        # Transport/settings
        _ovr('mcp_transport', 'MCP_TRANSPORT')
        _ovr('summary_chat', 'SUMMARY_CHAT')
        _ovr('url', 'MCP_HTTP_URL', path=['mcp_http_remote'])

        # SSH tunnel specific overrides
        _ovr('host', 'MCP_SSH_HOST', path=['mcp_ssh_tunnel'])
        _ovr('user', 'MCP_SSH_USER', path=['mcp_ssh_tunnel'])
        _ovr('key_path', 'MCP_SSH_KEY_PATH', path=['mcp_ssh_tunnel'])
        _ovr('remote_command', 'MCP_SSH_REMOTE_COMMAND', path=['mcp_ssh_tunnel'])

        # Do not propagate Telegram creds into child process from this agent

    def default_config(self) -> Dict[str, Any]:
        return {
            "use_userbot": True,
            "mcp_server_url": "http://localhost:3000",
            "chats": ["@telegram"],
            "ui_theme": "light",
            "log_level": "INFO"
        }

    def setup_logging(self):
        """Setup logging configuration"""
        import logging
        # Default to INFO to avoid debug noise; can be overridden by config
        log_level = getattr(logging, self.config.get('log_level', 'INFO').upper())
        
        # Create logs directory before attaching FileHandler
        import os
        os.makedirs('logs', exist_ok=True)

        logging.basicConfig(
            level=log_level,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('logs/telegram_agent.log'),
                logging.StreamHandler()
            ]
        )
        # Tame noisy libraries to WARNING regardless of global level
        logging.getLogger('httpx').setLevel(logging.WARNING)
        logging.getLogger('httpcore').setLevel(logging.WARNING)
        logging.getLogger('openai').setLevel(logging.WARNING)
        logging.getLogger('asyncio').setLevel(logging.WARNING)
        # Hide DEBUG traffic logs from our MCP client by default
        logging.getLogger('telegram_monitoring_agent.src.mcp_client').setLevel(logging.INFO)
        # Ensure our main agent logger at least INFO
        logging.getLogger('TelegramAgent').setLevel(max(logging.INFO, log_level))
        
        # Filter sensitive data from logs
        class SensitiveDataFilter(logging.Filter):
            def filter(self, record):
                sensitive_words = ['api_key', 'api_hash', 'bot_token', 'password', 'secret']
                if hasattr(record, 'msg') and isinstance(record.msg, str):
                    for word in sensitive_words:
                        if word in record.msg.lower():
                            record.msg = "[SENSITIVE DATA REDACTED]"
                            break
                return True

    def _chunk_list(self, items: list, size: int) -> list:
        """Split list into chunks of given size"""
        return [items[i:i+size] for i in range(0, len(items), size)]

    async def summarize_news_and_trends(self, messages: list, source_title: Optional[str] = None, source_username: Optional[str] = None) -> str:
        """Summarize messages focusing on AI news, trends, frameworks, and tools using a system prompt."""
        try:
            # Build conversation with system prompt
            system_prompt = (
                "Ты — аналитик новостей ИИ.\n"
                "Твоя задача: проанализировать сообщения из Telegram-чата и кратко выделить:\n"
                "1) Новости и анонсы в сфере нейросетей (модели, релизы, исследования).\n"
                "2) Тенденции развития и важные сдвиги на рынке/в технологиях.\n"
                "3) Отдельным блоком: новые фреймворки, библиотеки и инструменты для работы с нейросетями (название → краткое описание).\n"
                "4) Если присутствуют практические советы/гайды — вынеси их тезисно.\n"
                "Обязательные требования к оформлению:\n"
                "- В КАЖДОМ пункте указывай ссылку(и) на исходные сообщения канала, если это возможно (например, формат t.me/<username>/<messageId>).\n"
                "- Если в тексте встречаются внешние источники (статьи, репозитории, релизы) — обязательно добавляй прямые URL на эти источники.\n"
                "- Отвечай по-русски, структурировано по пунктам, без воды, с маркерами.\n"
            )

            # Prepare content from messages, appending per-message source links when possible
            lines: list[str] = []
            for m in messages:
                text = m.get('text', '')
                if not text:
                    continue
                display = m.get('from', {}).get('display', 'Unknown')
                link_suffix = ''
                try:
                    if source_username:
                        mid = int(m.get('id', 0))
                        if mid > 0:
                            link_suffix = f" [src: https://t.me/{source_username}/{mid}]"
                except Exception:
                    link_suffix = ''
                lines.append(f"{display}: {text}{link_suffix}")
            content = "\n".join(lines)

            user_prompt = (
                (f"Источник: {source_title}\n\n" if source_title else "") +
                "Проанализируй следующий батч сообщений и дай структурированную сводку по критериям из системного промпта:\n\n" +
                content
            )

            text = await self._llm_complete([
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
                max_tokens=min(350, int(self.config.get('deepseek_max_tokens', 2000))),
                temperature=float(self.config.get('deepseek_temperature', 0.3))
            )
            return (text or "").strip()
        except Exception as e:
            return f"LLM summarization error: {str(e)}"
        
        for handler in logging.getLogger().handlers:
            handler.addFilter(SensitiveDataFilter())
            
        # logs directory already ensured above

    def _load_last_seen(self):
        """Load last_seen_ids from state file if exists"""
        try:
            import os
            if os.path.exists(self.state_file):
                with open(self.state_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    if isinstance(data, dict):
                        # Keep only int ids
                        self.last_seen_ids = {str(k): int(v) for k, v in data.items() if str(k)}
                        self.logger.debug(f"Loaded last_seen_ids for {len(self.last_seen_ids)} chats from state")
        except Exception as e:
            self.logger.warning(f"Failed to load last_seen_ids: {e}")

    def _save_last_seen(self):
        """Persist last_seen_ids to state file"""
        try:
            import os
            os.makedirs('logs', exist_ok=True)
            with open(self.state_file, 'w', encoding='utf-8') as f:
                json.dump(self.last_seen_ids, f, ensure_ascii=False, indent=2)
        except Exception as e:
            self.logger.warning(f"Failed to save last_seen_ids: {e}")

    def get_llm_client(self):
        """Return LLM client and model name based on provider configuration"""
        provider = (self.config.get('llm_provider') or 'deepseek').lower()
        try:
            from openai import AsyncOpenAI
        except Exception as e:
            return None, None, f"OpenAI library not installed: {e}"

        import os as _os
        if provider == 'deepseek':
            # Read only from environment (e.g., .env): DEEPSEEK_API_KEY
            api_key = (_os.environ.get('DEEPSEEK_API_KEY') or '').strip()
            if not api_key:
                return None, None, "DeepSeek API key not configured"
            # DeepSeek is OpenAI-compatible via base_url
            client = AsyncOpenAI(api_key=api_key, base_url="https://api.deepseek.com")
            model = self.config.get('deepseek_model', 'deepseek-chat')
            return client, model, None
        elif provider == 'yandex':
            # Yandex handled via YandexGptUseCase in _llm_complete; here only validate env for compatibility
            iam = (_os.environ.get('YANDEX_IAM_TOKEN') or '').strip()
            apikey = (_os.environ.get('YANDEX_API_KEY') or '').strip()
            folder = (_os.environ.get('YANDEX_FOLDER_ID') or '').strip()
            if not folder or (not iam and not apikey):
                return None, None, "Yandex GPT credentials not configured"
            # Return placeholders; _llm_complete will use YandexGptUseCase
            return None, 'yandex', None
        else:
            return None, None, f"Unsupported llm_provider: {provider}"

    def _llm_is_configured(self) -> tuple[bool, Optional[str]]:
        provider = (self.config.get('llm_provider') or 'deepseek').lower()
        env = os.environ
        if provider == 'deepseek':
            if (env.get('DEEPSEEK_API_KEY') or '').strip():
                return True, None
            return False, 'DeepSeek API key not configured'
        elif provider == 'yandex':
            has_auth = (env.get('YANDEX_IAM_TOKEN') or env.get('YANDEX_API_KEY') or '').strip()
            has_folder = (env.get('YANDEX_FOLDER_ID') or '').strip()
            if has_auth and has_folder:
                return True, None
            return False, 'Yandex GPT credentials not configured (require YANDEX_IAM_TOKEN or YANDEX_API_KEY) and YANDEX_FOLDER_ID'
        return False, f'Unsupported llm_provider: {provider}'

    # ---- Scheduling helpers ----
    def _parse_report_times(self) -> list[dtime]:
        """Parse fixed times (HH:MM or HH:MM:SS) from monitor_report_times.
        Entries that look like cron (contain 4 or more spaces) are ignored here.
        """
        times_raw = self.monitor_report_times
        if not times_raw or not isinstance(times_raw, list):
            return []
        parsed: list[dtime] = []
        for s in times_raw:
            try:
                if not isinstance(s, str):
                    continue
                # Treat as fixed time only if it looks like HH:MM or HH:MM:SS
                if ' ' in s.strip():
                    # likely a cron spec, skip here
                    continue
                parts = [int(x) for x in s.strip().split(":")]
                if len(parts) == 2:
                    h, m = parts
                    parsed.append(dtime(hour=h, minute=m, second=0))
                elif len(parts) == 3:
                    h, m, sec = parts
                    parsed.append(dtime(hour=h, minute=m, second=sec))
                else:
                    raise ValueError("unsupported time format")
            except Exception:
                try:
                    self.logger.warning(f"Invalid time in monitor_report_times ignored: {s}")
                except Exception:
                    pass
        # Deduplicate and sort
        uniq = sorted({t for t in parsed})
        return uniq

    def _seconds_until_next_fixed(self, times: list[dtime]) -> Optional[tuple[float, str]]:
        """Return seconds until next fixed time and label. If no times, return None."""
        if not times:
            return None
        now = datetime.now()
        today = now.date()
        candidates = [datetime.combine(today, t) for t in times]
        future = [dt for dt in candidates if dt > now]
        if not future:
            # Next day earliest time
            next_dt = datetime.combine(today + timedelta(days=1), times[0])
        else:
            next_dt = min(future)
        delta = (next_dt - now).total_seconds()
        return max(delta, 0.0), next_dt.strftime('%H:%M:%S')

    def _parse_cron_entries(self) -> list[str]:
        """Extract cron-like 5-field specs from monitor_report_times.
        Supported format: "m h dom mon dow" with lists (a,b), ranges (a-b), steps (*/n). DOW: 0 or 7=Sun, 1=Mon.
        """
        specs: list[str] = []
        if not isinstance(self.monitor_report_times, list):
            return specs
        for s in self.monitor_report_times:
            if isinstance(s, str) and len(s.strip().split()) >= 5:
                specs.append(" ".join(s.strip().split()[:5]))
        return specs

    def _cron_field_match(self, value: int, spec: str, min_v: int, max_v: int) -> bool:
        """Check if a single cron field spec matches a value."""
        spec = spec.strip()
        if spec == '*':
            return True
        def expand_token(token: str) -> set[int]:
            # Handle step syntax
            if '/' in token:
                base, step_s = token.split('/', 1)
                step = int(step_s)
                if base == '*':
                    rng = range(min_v, max_v + 1)
                else:
                    # range or single
                    if '-' in base:
                        a, b = base.split('-', 1)
                        rng = range(int(a), int(b) + 1)
                    else:
                        v = int(base)
                        rng = range(v, v + 1)
                return {v for v in rng if (v - min_v) % step == 0}
            # Range
            if '-' in token:
                a, b = token.split('-', 1)
                return set(range(int(a), int(b) + 1))
            # Single number
            return {int(token)}

        allowed: set[int] = set()
        for part in spec.split(','):
            part = part.strip()
            if not part:
                continue
            try:
                allowed |= expand_token(part)
            except Exception:
                # invalid token -> no match
                return False
        return value in allowed

    def _seconds_until_next_cron(self, specs: list[str]) -> Optional[tuple[float, str]]:
        """Compute seconds until next time matching any of the cron specs.
        Returns (seconds, label) or None if no specs.
        """
        if not specs:
            return None
        now = datetime.now().replace(second=0, microsecond=0)
        start = now + timedelta(minutes=1)  # search from next minute
        max_iters = 366 * 24 * 60  # up to a year
        def matches(dt: datetime, spec: str) -> bool:
            fields = spec.split()
            if len(fields) < 5:
                return False
            m_s, h_s, dom_s, mon_s, dow_s = fields[:5]
            minute = dt.minute
            hour = dt.hour
            dom = dt.day
            mon = dt.month
            # Map Python weekday() (Mon=0..Sun=6) to cron (Sun=0 or 7)
            py_dow = dt.weekday()  # Mon=0..Sun=6
            cron_dow = (py_dow + 1) % 7  # Sun=0, Mon=1, ... Sat=6
            return (
                self._cron_field_match(minute, m_s, 0, 59) and
                self._cron_field_match(hour, h_s, 0, 23) and
                self._cron_field_match(dom, dom_s, 1, 31) and
                self._cron_field_match(mon, mon_s, 1, 12) and
                (self._cron_field_match(cron_dow, dow_s, 0, 6) or (dow_s.strip() == '7' and cron_dow == 0))
            )

        cur = start
        for _ in range(max_iters):
            for spec in specs:
                if matches(cur, spec):
                    seconds = (cur - datetime.now()).total_seconds()
                    label = cur.strftime('%Y-%m-%d %H:%M') + f" cron: {spec}"
                    return max(seconds, 0.0), label
            cur += timedelta(minutes=1)
        # Fallback: none found within a year
        return None

    async def _llm_complete(self, messages: list[dict], max_tokens: int, temperature: float) -> str:
        """Unified completion for configured LLM provider (DeepSeek or Yandex)."""
        provider = (self.config.get('llm_provider') or 'deepseek').lower()
        if provider == 'deepseek':
            client, model, err = self.get_llm_client()
            if err:
                raise RuntimeError(err)
            resp = await client.chat.completions.create(
                model=model,
                messages=messages,
                max_tokens=max_tokens,
                temperature=temperature,
            )
            return resp.choices[0].message.content.strip()
        elif provider == 'yandex':
            usecase = YandexGptUseCase()
            return await usecase.complete(messages, temperature=temperature, max_tokens=max_tokens)
        else:
            raise RuntimeError(f"Unsupported llm_provider: {provider}")

    async def start_continuous_monitoring(self):
        """Start continuous monitoring of chats"""
        print("Starting continuous monitoring...")
        fixed_times = self._parse_report_times()
        cron_specs = self._parse_cron_entries()
        if fixed_times or cron_specs:
            self.logger.info("monitor_interval_sec ignored due to monitor_report_times (schedule mode)")
            if fixed_times:
                self.logger.info(f"Fixed times: {[t.strftime('%H:%M:%S') for t in fixed_times]}")
            if cron_specs:
                self.logger.info(f"Cron specs: {cron_specs}")
        else:
            # Do NOT analyze immediately on startup when using plain interval
            try:
                self.logger.info(f"First run will start in {int(self.monitor_interval_sec)}s (interval mode)")
                await asyncio.sleep(self.monitor_interval_sec)
            except asyncio.CancelledError:
                return
        while True:
            try:
                if fixed_times or cron_specs:
                    # Compute next run among fixed times and cron specs
                    candidates: list[tuple[float, str]] = []
                    ft = self._seconds_until_next_fixed(fixed_times)
                    if ft:
                        candidates.append(ft)
                    ct = self._seconds_until_next_cron(cron_specs)
                    if ct:
                        candidates.append(ct)
                    if not candidates:
                        # No valid schedule -> fallback to interval
                        await self.start_monitoring()
                        await asyncio.sleep(self.monitor_interval_sec)
                        continue
                    delay, label = min(candidates, key=lambda x: x[0])
                    self.logger.info(f"Next scheduled monitoring run at {label} (in {int(delay)}s)")
                    await asyncio.sleep(delay)
                    await self.start_monitoring()
                    await asyncio.sleep(1)
                else:
                    await self.start_monitoring()
                    await asyncio.sleep(self.monitor_interval_sec)  # Interval from config
            except Exception as e:
                print(f"Monitoring error: {e}")
                await asyncio.sleep(30)  # Retry after 30 seconds
            
    async def start_monitoring(self):
        """Run single monitoring iteration across configured chats via MCP"""
        # Prevent overlapping iterations which can lead to duplicate summaries
        if self._monitor_lock.locked():
            self.logger.warning("Monitoring iteration skipped: previous iteration still running")
            return
        async with self._monitor_lock:
            chats = self.get_monitored_chats()
            if not chats:
                self.logger.warning("No chats configured to monitor")
                return
            # Process chats sequentially to avoid any potential interleaving across requests
            for chat_id in chats:
                await self.monitor_chat(chat_id)

    async def monitor_chat(self, chat_id: str):
        """Monitor a specific chat using MCP. Assumes MCP session is already open by the caller."""
        try:
            # Resolve chat first with timeout
            self.logger.debug(f"Resolving chat: {chat_id}")
            chat_info = await asyncio.wait_for(
                self.mcp_client.resolve_chat(chat_id),
                timeout=10.0
            )
            if not chat_info:
                self.logger.warning(f"Could not resolve chat: {chat_id}")
                return
                
            # Pick a reference to fetch history: prefer username, fallback to id, else original input
            chat_ref = chat_info.get('username') or str(chat_info.get('id')) or chat_id
            self.logger.info(f"Resolved chat '{chat_id}' -> ref='{chat_ref}', title='{chat_info.get('title')}', type='{chat_info.get('type')}'")

            # Fetch full history since last_seen using pagination
            last_seen = int(self.last_seen_ids.get(chat_ref, 0))
            self.logger.debug(
                f"Fetching history for {chat_ref} starting from last_seen_id={last_seen} (batch={self.page_size})"
            )

            msgs = []
            max_id_cursor = None  # paginate older within (min_id; max_id]
            while True:
                try:
                    batch = await asyncio.wait_for(
                        self.mcp_client.fetch_history(
                            chat_ref,
                            page_size=self.page_size,
                            min_id=last_seen if last_seen > 0 else None,
                            max_id=max_id_cursor
                        ),
                        timeout=15.0
                    )
                except asyncio.TimeoutError:
                    self.logger.warning(f"Timeout fetching history page for {chat_ref}")
                    break

                if not batch or 'messages' not in batch:
                    break

                page_msgs = batch['messages'] or []
                if not page_msgs:
                    break

                # Extend and move cursor to fetch older messages above last_seen
                msgs.extend(page_msgs)
                # Determine next max_id (strictly less than current min id)
                try:
                    current_min = min(int(m.get('id', 0)) for m in page_msgs)
                except Exception:
                    current_min = None
                # Stop if page smaller than batch, otherwise set cursor and continue
                if len(page_msgs) < self.page_size or not current_min:
                    break
                max_id_cursor = current_min - 1

            if not msgs:
                self.logger.info(f"No messages returned for {chat_ref}")
                return

            self.logger.debug(f"Fetched total {len(msgs)} message(s) for {chat_ref} before de-dup")
            # Query server-side unread counters
            try:
                unread_info = await asyncio.wait_for(
                    self.mcp_client.get_unread_count(chat_ref),
                    timeout=10.0
                )
            except asyncio.TimeoutError:
                unread_info = {}
                self.logger.warning(f"Timeout getting unread count for {chat_ref}")
            unread = 0
            if isinstance(unread_info, dict):
                try:
                    unread = int(unread_info.get('unread', 0))
                except Exception:
                    unread = 0

            # Deduplicate: process only messages with id > last_seen_id
            def _mid(m: Dict[str, Any]) -> int:
                try:
                    return int(m.get('id', 0))
                except Exception:
                    return 0
            new_msgs = [m for m in msgs if _mid(m) > last_seen]
            self.logger.debug(f"New messages for {chat_ref} since {last_seen}: {len(new_msgs)}")
            if new_msgs:
                # Sort ascending by id to preserve chronology, update last_seen
                new_msgs.sort(key=_mid)
                new_max = max((_mid(m) for m in new_msgs), default=last_seen)
                self.last_seen_ids[chat_ref] = max(self.last_seen_ids.get(chat_ref, 0), new_max)
                # Persist state after update
                self._save_last_seen()
            self.logger.info(f"History for {chat_ref}: {len(msgs)} messages, unread: {unread}. New since last_seen_id={last_seen}: {len(new_msgs)}")

            if not new_msgs:
                return

            # Apply filters and chunk by configured size
            filtered = [m for m in new_msgs if self.should_process_message(m)]
            self.logger.info(f"Filtered messages for {chat_ref}: {len(filtered)} of {len(new_msgs)} passed filters")
            if not filtered:
                self.logger.warning(f"No messages passed filters for {chat_ref} (0/{len(new_msgs)}).")
                # Soft mode: fall back to all new messages
                if self.filter_mode == 'soft' and new_msgs:
                    self.logger.info(f"filter_mode=soft: using all {len(new_msgs)} new messages for {chat_ref} to build summary")
                    filtered = new_msgs
                else:
                    # Optionally send a placeholder report
                    if self.report_if_empty:
                        target_chat = self.summary_chat or chat_ref
                        title = chat_info.get('title') or chat_ref
                        placeholder = (
                            f"🧠 Сводка для {title}: релевантных сообщений по фильтрам не найдено. "
                            f"Новых сообщений за период: {len(new_msgs)}."
                        )
                        try:
                            send_res = await self.mcp_client.send_message(target_chat, placeholder)
                            if isinstance(send_res, dict) and send_res.get("message_id"):
                                self.logger.info(f"Empty report note sent to {target_chat} for {chat_ref}")
                            else:
                                self.logger.error(f"Failed to send empty report note to {target_chat}: {send_res}")
                        except Exception as e:
                            self.logger.error(f"Error sending empty report note for {chat_ref}: {e}")
                    return

            chunks = self._chunk_list(filtered, self.chunk_size)
            self.logger.info(f"Processing {len(filtered)} new messages in {len(chunks)} chunks for {chat_ref}")

            # Summarize each chunk and send
            target_chat = self.summary_chat or chat_ref
            for idx, chunk in enumerate(chunks, start=1):
                try:
                    # Ensure LLM is configured before summarizing
                    ok, err = self._llm_is_configured()
                    if not ok:
                        self.logger.warning(f"Skipping summarization for {chat_ref}: {err}")
                        continue
                    summary = await self.summarize_news_and_trends(
                        chunk,
                        source_title=chat_info.get('title') or chat_ref,
                        source_username=(chat_info.get('username') if isinstance(chat_info, dict) else None)
                    )
                    if summary and summary.strip():
                        prefix = f"🧠 Сводка #{idx}/{len(chunks)} для {chat_info.get('title') or chat_ref}:\n\n"
                        send_res = await self.mcp_client.send_message(target_chat, prefix + summary)
                        if isinstance(send_res, dict) and send_res.get("message_id"):
                            self.logger.info(f"Summary chunk {idx}/{len(chunks)} sent to {target_chat}")
                        else:
                            self.logger.error(f"Failed to send summary chunk {idx} to {target_chat}: {send_res}")
                except Exception as e:
                    self.logger.error(f"Error summarizing/sending chunk {idx}: {e}")
                    
        except asyncio.TimeoutError:
            self.logger.error(f"Timeout monitoring chat {chat_id}")
        except Exception as e:
            self.logger.error(f"Error monitoring chat {chat_id}: {e}")
            
    async def process_message(self, message: Dict[str, Any]):
        """Process a single message"""
        text = message.get('text', '')
        
        # Apply filters first
        if not self.should_process_message(message):
            return
        
        if text:
            # Parse message details
            sender = message.get('from', {}).get('display', 'Unknown')
            date = message.get('date', 'Unknown')
            
            print(f"[{date}] Message from {sender}: {text[:100]}...")
            
            # For now, just summarize if it's a query
            if text.startswith('?') or text.lower().startswith('summarize'):
                summary = await self.summarize_with_llm({'messages': [message]})
                print(f"Summary: {summary}")
                
    def should_process_message(self, message: Dict[str, Any]) -> bool:
        """Check if message passes filters"""
        filters = self.config.get('filters', {})
        
        # Check minimum length
        min_length = filters.get('min_length', 0)
        text = message.get('text', '')
        if len(text) < min_length:
            return False
        
        # Check keywords
        keywords = filters.get('keywords', [])
        if keywords:
            has_keyword = any(keyword.lower() in text.lower() for keyword in keywords)
            if not has_keyword:
                return False
        
        # Check excluded senders
        exclude_senders = filters.get('exclude_senders', [])
        sender = message.get('from', {}).get('display', '')
        if sender in exclude_senders:
            return False
        
        return True

    async def test_connection(self) -> bool:
        """Test MCP stdio connection (initialize, tools/list, resolve a test chat)."""
        try:
            async with self.mcp_client:
                # initialize and tools/list
                await self.mcp_client.initialize()
                tools = await self.mcp_client.list_tools()
                if tools:
                    self.logger.info(f"MCP tools: {[t.get('name') for t in tools if isinstance(t, dict)]}")
                test_chat = self.config.get('chats', [])[0] if self.config.get('chats') else '@telegram'
                chat_info = await self.mcp_client.resolve_chat(test_chat)
                if not chat_info:
                    print("MCP connection test failed: Could not resolve test chat")
                    return False
                
                print(f"MCP connection OK: Resolved {test_chat} to {chat_info.get('title', 'Unknown')}")
                return True
                
        except Exception as e:
            print(f"Connection test failed: {e}")
            return False

    async def summarize_with_llm(self, history: Dict[str, Any]) -> str:
        """Summarize messages using configured LLM (DeepSeek or Yandex)."""
        try:
            messages = history.get('messages', [])
            if not messages:
                return "No messages to summarize"

            content = "\n".join([
                f"{msg.get('from', {}).get('display', 'Unknown')}: {msg.get('text', '')}"
                for msg in messages
            ])

            prompt = (
                "Суммируй следующие сообщения Telegram кратко и по-русски, выдели ключевые пункты и выводы.\n\n"
                f"{content}"
            )

            text = await self._llm_complete(
                [{"role": "user", "content": prompt}],
                max_tokens=min(200, int(self.config.get('deepseek_max_tokens', 2000))),
                temperature=float(self.config.get('deepseek_temperature', 0.3))
            )
            return (text or "").strip()
        except Exception as e:
            return f"LLM summarization error: {str(e)}"

    async def analyze_sentiment_and_intent(self, message: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze sentiment and intent of a message using LLM"""
        try:
            # We will call configured LLM via _llm_complete

            text = message.get('text', '')
            if not text:
                return {"sentiment": "neutral", "intent": "unknown", "confidence": 0}

            prompt = (
                "Определи для сообщения: 1) тональность (positive, negative, neutral), "
                "2) намерение (question, statement, command, request, complaint, praise, other), "
                "3) confidence (0-1). Ответ строго в JSON: {\"sentiment\": \"...\", \"intent\": \"...\", \"confidence\": 0.x}.\n\n"
                f"Message: {text}"
            )

            result_text = await self._llm_complete(
                [{"role": "user", "content": prompt}],
                max_tokens=120,
                temperature=0.2
            )
            import json as _json
            result_text = (result_text or "").strip()
            try:
                return _json.loads(result_text)
            except _json.JSONDecodeError:
                sentiment = "neutral"
                intent = "statement"
                confidence = 0.5
                low = result_text.lower()
                if "positive" in low:
                    sentiment = "positive"
                elif "negative" in low:
                    sentiment = "negative"
                if "question" in low or '?' in text:
                    intent = "question"
                return {"sentiment": sentiment, "intent": intent, "confidence": confidence}
        except Exception:
            return {"sentiment": "error", "intent": "error", "confidence": 0}

    async def extract_features(self, message: Dict[str, Any]) -> Dict[str, Any]:
        """Extract key features from message using LLM"""
        try:
            # Use configured LLM via _llm_complete

            text = message.get('text', '')
            if not text:
                return {"entities": [], "topics": [], "urgency": "low"}

            prompt = (
                "Извлеки из сообщения: 1) именованные сущности (люди, организации, локации), "
                "2) основные темы, 3) срочность (high, medium, low), 4) даты/временные ссылки. "
                "Ответ строго в JSON: {\"entities\": [...], \"topics\": [...], \"urgency\": \"...\", \"dates\": [...]}.\n\n"
                f"Message: {text}"
            )

            result_text = await self._llm_complete(
                [{"role": "user", "content": prompt}],
                max_tokens=180,
                temperature=0.2
            )
            import json as _json
            result_text = (result_text or "").strip()
            try:
                return _json.loads(result_text)
            except _json.JSONDecodeError:
                return {"entities": [], "topics": [], "urgency": "low", "dates": []}
        except Exception as e:
            return {"entities": [], "topics": [], "urgency": "low", "error": str(e)}

    async def generate_response(self, message: Dict[str, Any], analysis: Dict[str, Any] = None) -> str:
        """Generate automated response using LLM"""
        try:
            # Use configured LLM via _llm_complete

            text = message.get('text', '')
            sender = message.get('from', {}).get('display', 'Unknown')

            if not analysis:
                analysis = await self.analyze_sentiment_and_intent(message)

            sentiment = analysis.get('sentiment', 'neutral')
            intent = analysis.get('intent', 'statement')

            prompt = (
                "Сгенерируй уместный, профессиональный и краткий ответ на русском на следующее сообщение Telegram.\n"
                f"Оригинал: {text}\n"
                f"Отправитель: {sender}\n"
                f"Тональность: {sentiment}\n"
                f"Намерение: {intent}"
            )

            result_text = await self._llm_complete(
                [{"role": "user", "content": prompt}],
                max_tokens=160,
                temperature=float(self.config.get('deepseek_temperature', 0.7))
            )
            return (result_text or "").strip()
        except Exception as e:
            return f"Response generation error: {str(e)}"

    async def send_auto_response(self, chat_id: str, message: Dict[str, Any]):
        """Send automated response to chat"""
        try:
            # Analyze the message
            analysis = await self.analyze_sentiment_and_intent(message)
            
            # Generate response
            response_text = await self.generate_response(message, analysis)
            
            # Send response via MCP
            result = await self.mcp_client.send_message(chat_id, response_text)
            
            if result:
                print(f"Auto-response sent to {chat_id}: {response_text[:50]}...")
            else:
                print(f"Failed to send auto-response to {chat_id}")
                
        except Exception as e:
            print(f"Error sending auto-response: {e}")
            
    async def send_notification(self, message: str, target_chat: str = None):
        """Send notification message"""
        try:
            if not target_chat:
                target_chat = self.config.get('chats', [])[0] if self.config.get('chats') else '@telegram'
            
            result = await self.mcp_client.send_message(target_chat, f"🔔 {message}")
            
            if result:
                self.logger.info(f"Notification sent: {message}")
            else:
                self.logger.error(f"Failed to send notification")
                
        except Exception as e:
            self.logger.error(f"Error sending notification: {e}")
            
    async def forward_message_to_admin(self, message: Dict[str, Any], chat_id: str):
        """Forward important message to admin chat"""
        try:
            admin_chat = self.config.get('admin_chat', '@admin')
            message_id = message.get('id')
            
            if message_id:
                result = await self.mcp_client.forward_message(chat_id, admin_chat, message_id)
                
                if result:
                    print(f"Message forwarded to admin: {message.get('text', '')[:50]}...")
                else:
                    print(f"Failed to forward message to admin")
                    
        except Exception as e:
            print(f"Error forwarding message: {e}")

    async def health_check(self) -> Dict[str, Any]:
        """Perform health check of the system"""
        health_status = {
            "timestamp": str(asyncio.get_event_loop().time()),
            "status": "healthy",
            "checks": {}
        }
        
        # Check MCP connection
        try:
            test_chat = self.config.get('chats', [])[0] if self.config.get('chats') else '@telegram'
            # If MCP stdio session is already open, reuse it to avoid extra start/stop cycles
            if getattr(self.mcp_client, "process", None):
                chat_info = await self.mcp_client.resolve_chat(test_chat)
            else:
                async with self.mcp_client:
                    chat_info = await self.mcp_client.resolve_chat(test_chat)
            health_status["checks"]["mcp_connection"] = "healthy" if chat_info else "unhealthy"
        except Exception as e:
            health_status["checks"]["mcp_connection"] = f"error: {str(e)}"
            health_status["status"] = "unhealthy"
        
        # Check Telegram connection
        if (self.mcp_transport == "http") and health_status["checks"].get("mcp_connection") == "healthy":
            # When using HTTP MCP and it is healthy, rely on MCP as Telegram backend
            health_status["checks"]["telegram_connection"] = "via_mcp"
        elif self.telegram_client:
            try:
                # Avoid interactive prompts during health check
                await self.telegram_client.connect()
                try:
                    authorized = await self.telegram_client.is_user_authorized()
                except Exception:
                    # For bot clients, is_user_authorized may not exist; try get_me
                    authorized = False
                me = None
                if authorized:
                    me = await self.telegram_client.get_me()
                    health_status["checks"]["telegram_connection"] = "healthy" if me else "unhealthy"
                else:
                    # Try get_me for bot; if fails, mark as needs_login
                    try:
                        me = await self.telegram_client.get_me()
                        health_status["checks"]["telegram_connection"] = "healthy" if me else "unhealthy"
                    except Exception:
                        health_status["checks"]["telegram_connection"] = "needs_login"
                        health_status["status"] = "unhealthy"
                await self.telegram_client.disconnect()
            except Exception as e:
                health_status["checks"]["telegram_connection"] = f"error: {str(e)}"
                health_status["status"] = "unhealthy"
        else:
            health_status["checks"]["telegram_connection"] = "not_configured"
        
        # Check LLM API (consider provider)
        provider = (self.config.get('llm_provider') or 'deepseek').lower()
        if provider == 'deepseek':
            if self.config.get('deepseek_api_key') and self.config.get('deepseek_api_key').strip() != '':
                health_status["checks"]["llm_api"] = "configured (deepseek)"
            else:
                health_status["checks"]["llm_api"] = "not_configured"
        else:
            health_status["checks"]["llm_api"] = f"configured ({provider})" if self.config.get(f"{provider}_api_key", '').strip() else "not_configured"

        # Additional info
        health_status["checks"]["monitored_chats"] = len(self.config.get('chats', []))

        # Derive overall status from checks if not already set to unhealthy by exceptions
        if health_status["status"] == "healthy":
            for k, v in health_status["checks"].items():
                if isinstance(v, str) and (v.startswith("error:") or v == "unhealthy" or v == "needs_login"):
                    health_status["status"] = "unhealthy"
                    break

        chats = self.get_monitored_chats()
        health_status["checks"]["monitored_chats"] = len(chats)
        
        self.logger.info(f"Health check completed: {health_status['status']}")
        return health_status

    async def reconnect_mcp(self) -> bool:
        """Reconnect to MCP server"""
        try:
            self.logger.info("Attempting to reconnect to MCP server...")
            # Test connection
            test_chat = self.config.get('chats', [])[0] if self.config.get('chats') else '@telegram'
            async with self.mcp_client:
                chat_info = await self.mcp_client.resolve_chat(test_chat)
            if chat_info:
                self.logger.info("MCP reconnection successful")
                return True
            else:
                self.logger.error("MCP reconnection failed: Could not resolve test chat")
                return False
        except Exception as e:
            self.logger.error(f"MCP reconnection error: {e}")
            return False
            
    async def reconnect_telegram(self) -> bool:
        """Reconnect to Telegram"""
        if not self.telegram_client:
            self.logger.warning("No Telegram client to reconnect")
            return False
            
        try:
            self.logger.info("Attempting to reconnect to Telegram...")
            await self.telegram_client.disconnect()
            
            # Reinitialize
            if self.config.get("use_userbot", True):
                self.init_userbot()
            else:
                self.init_bot()
                
            if self.telegram_client:
                await self.telegram_client.start()
                me = await self.telegram_client.get_me()
                if me:
                    self.logger.info(f"Telegram reconnection successful: {me.username}")
                    return True
                
            self.logger.error("Telegram reconnection failed")
            return False
            
        except Exception as e:
            self.logger.error(f"Telegram reconnection error: {e}")
            return False
            
    async def ensure_connections(self):
        """Ensure all connections are healthy, reconnect if needed"""
        health = await self.health_check()
        
        if health['checks'].get('mcp_connection') != 'healthy':
            await self.reconnect_mcp()
            
        if health['checks'].get('telegram_connection') not in ['healthy', 'not_configured']:
            await self.reconnect_telegram()

    async def process_user_query(self, query: str) -> str:
        """Process user query and return response"""
        try:
            # For now, just echo back with processing info
            # In the future, this could integrate with the MCP client
            return f"Processed query: {query}\nAgent is running and monitoring configured chats."
        except Exception as e:
            return f"Error processing query: {str(e)}"

    def get_monitored_chats(self) -> list:
        """Get list of monitored chats"""
        return self.config.get('chats', [])

    async def _monitor_once(self) -> None:
        """Perform a single monitoring pass over configured chats using an already-open MCP session."""
        chats = self.get_monitored_chats()
        page_size = int(self.config.get('page_size', 10))
        for chat in chats:
            try:
                # Read recent messages
                data = await self.mcp_client.read_messages(chat, page_size=page_size)
                messages = (data or {}).get('messages', []) if isinstance(data, dict) else []
                # Optionally process/analyze messages here. For now, just log counts.
                self.logger.debug(f"Fetched {len(messages)} messages from {chat}")
            except asyncio.TimeoutError:
                self.logger.error(f"Timeout monitoring chat {chat}")
            except Exception as e:
                self.logger.error(f"Error monitoring chat {chat}: {e}")

    async def start_continuous_monitoring(self) -> None:
        """Run continuous monitoring loop using a single long-lived MCP session, with schedule support.
        - If monitor_report_times is set (fixed times and/or cron), interval is ignored and runs happen at schedule.
        - Otherwise uses interval mode, and the first run is delayed by one interval (no instant analysis on startup).
        """
        interval = int(self.monitor_interval_sec)
        chats = self.get_monitored_chats()
        fixed_times = self._parse_report_times()
        cron_specs = self._parse_cron_entries()
        if fixed_times or cron_specs:
            self.logger.info("monitor_interval_sec ignored due to monitor_report_times (schedule mode)")
            if fixed_times:
                self.logger.info(f"Fixed times: {[t.strftime('%H:%M:%S') for t in fixed_times]}")
            if cron_specs:
                self.logger.info(f"Cron specs: {cron_specs}")
            self.logger.info(f"Monitoring loop started: {len(chats)} chat(s), mode=schedule, transport={self.mcp_transport}")
        else:
            self.logger.info(f"Monitoring loop started: {len(chats)} chat(s), interval={interval}s, transport={self.mcp_transport}")

        # Keep one stdio session open to avoid concurrent process starts and interleaved frames
        async with self.mcp_client:
            try:
                await self.mcp_client.initialize()
            except Exception:
                pass

            # Initial wait: in interval mode wait one full interval; in schedule mode wait until the next scheduled time
            if fixed_times or cron_specs:
                candidates: list[tuple[float, str]] = []
                ft = self._seconds_until_next_fixed(fixed_times)
                if ft:
                    candidates.append(ft)
                ct = self._seconds_until_next_cron(cron_specs)
                if ct:
                    candidates.append(ct)
                if candidates:
                    delay, label = min(candidates, key=lambda x: x[0])
                    self.logger.info(f"Next scheduled monitoring run at {label} (in {int(delay)}s)")
                    try:
                        await asyncio.sleep(delay)
                    except asyncio.CancelledError:
                        return
            else:
                try:
                    self.logger.info(f"First run will start in {interval}s (interval mode)")
                    await asyncio.sleep(interval)
                except asyncio.CancelledError:
                    return

            # Main loop
            while True:
                try:
                    await self.start_monitoring()
                except asyncio.CancelledError:
                    break
                except Exception as e:
                    self.logger.error(f"Monitoring iteration error: {e}")

                # Wait until next run
                try:
                    if fixed_times or cron_specs:
                        candidates2: list[tuple[float, str]] = []
                        ft2 = self._seconds_until_next_fixed(fixed_times)
                        if ft2:
                            candidates2.append(ft2)
                        ct2 = self._seconds_until_next_cron(cron_specs)
                        if ct2:
                            candidates2.append(ct2)
                        if not candidates2:
                            # Fallback to interval if schedule empty
                            await asyncio.sleep(interval)
                            continue
                        delay2, label2 = min(candidates2, key=lambda x: x[0])
                        self.logger.info(f"Next scheduled monitoring run at {label2} (in {int(delay2)}s)")
                        await asyncio.sleep(delay2)
                        # tiny guard
                        await asyncio.sleep(1)
                    else:
                        await asyncio.sleep(interval)
                except asyncio.CancelledError:
                    break

    def run(self):
        """Run the agent"""
        print("Starting Telegram Monitoring Agent...")
        self.ui.run()

if __name__ == "__main__":
    agent = TelegramAgent()
    agent.run()
