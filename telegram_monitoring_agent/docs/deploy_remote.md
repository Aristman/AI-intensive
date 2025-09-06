# Deploy: Remote Server (Agent + MCP Telegram Server)

This guide describes how to deploy the Telegram Monitoring Agent together with the Python MCP Telegram server on a remote host. Includes single-host and split-host setups, environment preparation, login/session management, and background run options (nohup/systemd/Windows PowerShell).

## Topology Options

- Single host (recommended to start):
  - Both components run on the same remote machine via STDIO:
    - MCP Server: `python -u -m mcp_servers.telegram_mcp_server_py.main`
    - Agent: `python telegram_monitoring_agent/main.py`
- Split host via SSH:
  - Agent runs on Host A; MCP Server runs on Host B via SSH stdio tunnel.
  - Configure `config/config.json` → `mcp_ssh_tunnel.enabled = true` and set remote command.

## Prerequisites

- Python 3.9+ installed on the remote host.
- (Optional) Tkinter for UI if you need to open the agent UI on the remote host.
- Access to Telegram credentials. For the server, prefer bot token.

## 1) Clone repository on the remote host

```bash
# On the remote host
git clone <YOUR_REPO_URL> AI-intensive
cd AI-intensive
```

## 2) Create Python virtual environment and install dependencies

```bash
# Linux
python3 -m venv .venv
source .venv/bin/activate

# Windows PowerShell
python -m venv .venv
. .venv\Scripts\Activate.ps1

# Install agent deps
pip install -r telegram_monitoring_agent/requirements.txt

# Install MCP server deps
pip install -r mcp_servers/telegram_mcp_server_py/requirements.txt
```

## 3) Configure MCP Telegram server (Python)

Create `.env` in `mcp_servers/telegram_mcp_server_py/`:

```env
# Prefer bot auth
TELEGRAM_BOT_TOKEN=123456:ABC...
# Optional custom session file path
# TELEGRAM_SESSION_FILE=/opt/ai-intensive/telegram_session.txt

# OR user (MTProto) — requires pre-created session and is not recommended for headless MCP
# TELEGRAM_API_ID=...
# TELEGRAM_API_HASH=...
# TELEGRAM_PHONE_NUMBER=+1234567890
```

Create or update a session using the CLI utility (only once):

```bash
# Uses values from .env when arguments omitted
python -m mcp_servers.telegram_mcp_server_py.cli_login
```

This writes a session string to `mcp_servers/telegram_mcp_server_py/session.txt` (or `TELEGRAM_SESSION_FILE` path). The server will reuse it non-interactively.

## 4) Configure the Agent

Edit `telegram_monitoring_agent/config/config.json` as needed:

- Ensure stdio transport:
```json
{
  "mcp_transport": "stdio",
  "mcp_server_command": "python -u -m mcp_servers.telegram_mcp_server_py.main",
  "mcp_env_vars": {}
}
```
- Update chat list, logging level, LLM provider settings, etc.
- Do NOT put Telegram credentials into the agent config.

### Split-host via SSH (optional)

If you want MCP to run on a different server:

```json
{
  "mcp_transport": "stdio",
  "mcp_ssh_tunnel": {
    "enabled": true,
    "host": "mcp.remote.host",
    "user": "ubuntu",
    "key_path": "~/.ssh/id_rsa",
    "port": 22,
    "remote_command": "python -u -m mcp_servers.telegram_mcp_server_py.main"
  }
}
```

Set up the same repo and environment on the remote MCP host. The agent will execute the `remote_command` via SSH and connect stdio.

## 5) Test locally on the remote host

```bash
# List tools via the agent
python telegram_monitoring_agent/main.py --list-tools

# (Optional) run a quick test that calls MCP resolve chat
python telegram_monitoring_agent/main.py --test-mcp
```

## 6) Running in Background

You can run both the MCP server and the Agent in the background. Since the Agent already starts the MCP server as a child process via stdio, you normally only need to background the Agent.

### Linux/macOS (nohup)

```bash
# From repo root, with venv activated
nohup python -u telegram_monitoring_agent/main.py > logs/agent.out 2>&1 &
echo $! > logs/agent.pid
# To stop:
kill $(cat logs/agent.pid)
```

If you ever need to run the MCP server standalone in the background:

```bash
nohup python -u -m mcp_servers.telegram_mcp_server_py.main > logs/mcp.out 2>&1 &
echo $! > logs/mcp.pid
```

### Linux (systemd services)

Create service files (example paths, adjust to your environment):

`/etc/systemd/system/ai-mcp.service`
```ini
[Unit]
Description=AI Intensive - Telegram MCP Server (Python)
After=network.target

[Service]
WorkingDirectory=/opt/AI-intensive
ExecStart=/opt/AI-intensive/.venv/bin/python -u -m mcp_servers.telegram_mcp_server_py.main
Restart=always
RestartSec=5
StandardOutput=append:/opt/AI-intensive/logs/mcp.out
StandardError=append:/opt/AI-intensive/logs/mcp.err
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
```

`/etc/systemd/system/ai-agent.service`
```ini
[Unit]
Description=AI Intensive - Telegram Monitoring Agent
After=network.target
Requires=ai-mcp.service

[Service]
WorkingDirectory=/opt/AI-intensive
ExecStart=/opt/AI-intensive/.venv/bin/python -u telegram_monitoring_agent/main.py
Restart=always
RestartSec=5
StandardOutput=append:/opt/AI-intensive/logs/agent.out
StandardError=append:/opt/AI-intensive/logs/agent.err
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable ai-mcp.service ai-agent.service
sudo systemctl start ai-mcp.service ai-agent.service
# Status
systemctl status ai-mcp.service ai-agent.service
```

### Windows (PowerShell, start in background)

Start the agent in background:

```powershell
$logDir = "logs"; if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
Start-Process -FilePath "python" -ArgumentList "-u", "telegram_monitoring_agent/main.py" -WindowStyle Hidden -RedirectStandardOutput "logs/agent.out" -RedirectStandardError "logs/agent.err"
```

If you want to run the MCP server standalone as a background process:

```powershell
Start-Process -FilePath "python" -ArgumentList "-u", "-m", "mcp_servers.telegram_mcp_server_py.main" -WindowStyle Hidden -RedirectStandardOutput "logs/mcp.out" -RedirectStandardError "logs/mcp.err"
```

For Windows services consider NSSM or the Windows Service Wrapper to register Python scripts as services.

## Security Notes

- Keep Telegram credentials only in the MCP server `.env` (or secure secret store) on the host where MCP runs.
- Do not place credentials in the agent config.
- Restrict access to the repository and logs (logs may contain meta information but should not include secrets).

## Troubleshooting

- No tools listed: verify MCP server dependencies installed, session exists (`cli_login.py`), and `.env` values are correct.
- MCP timeouts: ensure stdout is not used for logging; only stderr. Our server enforces this.
- SSH tunnel issues: check SSH key permissions, firewall rules, and that `remote_command` is correct and resolves Python from the expected environment.
- Windows: if PowerShell background process exits, check the paths and install a service wrapper.
