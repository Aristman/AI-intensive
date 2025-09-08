#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FS MCP Server (Python, STDIO)
Implements a minimal JSON-RPC like protocol over stdin/stdout with methods:
- initialize
- tools/list
- tools/call (fs_list, fs_read, fs_write, fs_delete)

Sandbox root: FS_ROOT env or current working directory.
Each request is a single JSON line (UTF-8). Response is a single JSON line.
"""
import sys
import os
import json
import traceback
from typing import Any, Dict, List

VERSION = "0.1.0"

FS_ROOT = os.path.abspath(os.environ.get("FS_ROOT", os.getcwd()))

TOOLS = [
    {
        "name": "fs_list",
        "description": "List directory entries",
        "input_schema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]},
    },
    {
        "name": "fs_read",
        "description": "Read file preview (64KB)",
        "input_schema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]},
    },
    {
        "name": "fs_write",
        "description": "Write file with optional createDirs and overwrite",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "content": {"type": "string"},
                "createDirs": {"type": "boolean"},
                "overwrite": {"type": "boolean"},
            },
            "required": ["path", "content"],
        },
    },
    {
        "name": "fs_delete",
        "description": "Delete file or directory (recursive)",
        "input_schema": {"type": "object", "properties": {"path": {"type": "string"}, "recursive": {"type": "boolean"}}, "required": ["path"]},
    },
]

MAX_PREVIEW = 64 * 1024


def log(msg: str, **fields) -> None:
    rec = {"event": "log", "message": msg}
    if fields:
        rec.update(fields)
    print(json.dumps(rec, ensure_ascii=False), file=sys.stderr)


def within_root(path: str) -> bool:
    try:
        ap = os.path.abspath(path)
        rr = FS_ROOT
        # commonpath raises if paths are on different drives on Windows
        common = os.path.commonpath([ap, rr])
        return common == rr
    except Exception:
        return False


def resolve_path(user_path: str) -> str:
    if not user_path or not user_path.strip():
        raise ValueError("Empty path")
    candidate = os.path.abspath(user_path if os.path.isabs(user_path) else os.path.join(FS_ROOT, user_path))
    if not within_root(candidate):
        raise PermissionError(f"Path escapes root: {candidate}")
    return candidate


def handle_initialize(req: Dict[str, Any]) -> Dict[str, Any]:
    log("initialize")
    return {"ok": True, "server": "fs_mcp_server_py", "version": VERSION, "fs_root": FS_ROOT}


def handle_tools_list(req: Dict[str, Any]) -> Dict[str, Any]:
    log("tools/list")
    return {"ok": True, "tools": TOOLS}


def handle_fs_list(args: Dict[str, Any]) -> Dict[str, Any]:
    path = args.get("path", ".")
    abs_path = resolve_path(path)
    if not os.path.exists(abs_path):
        return {"ok": True, "path": os.path.relpath(abs_path, FS_ROOT), "entries": [], "message": "Not found"}
    if not os.path.isdir(abs_path):
        return {"ok": False, "message": "Not a directory"}
    entries: List[Dict[str, Any]] = []
    for name in sorted(os.listdir(abs_path)):
        full = os.path.join(abs_path, name)
        if os.path.isdir(full):
            entries.append({"name": name, "isDir": True})
        else:
            try:
                size = os.path.getsize(full)
            except Exception:
                size = None
            entries.append({"name": name, "isDir": False, **({"size": size} if size is not None else {})})
    return {"ok": True, "path": os.path.relpath(abs_path, FS_ROOT), "entries": entries}


def handle_fs_read(args: Dict[str, Any]) -> Dict[str, Any]:
    path = args.get("path", "")
    abs_path = resolve_path(path)
    if not os.path.exists(abs_path):
        return {"ok": False, "message": "File not found", "path": os.path.relpath(abs_path, FS_ROOT)}
    if os.path.isdir(abs_path):
        return {"ok": False, "message": "Is a directory", "path": os.path.relpath(abs_path, FS_ROOT)}
    try:
        with open(abs_path, "rb") as f:
            data = f.read(MAX_PREVIEW)
        content = data.decode("utf-8", errors="replace")
        size = os.path.getsize(abs_path)
        return {
            "ok": True,
            "path": os.path.relpath(abs_path, FS_ROOT),
            "size": size,
            "contentSnippet": content,
            "message": f"Read preview {min(size, MAX_PREVIEW)} bytes",
        }
    except Exception as e:
        return {"ok": False, "message": f"Read error: {e}"}


def handle_fs_write(args: Dict[str, Any]) -> Dict[str, Any]:
    path = args.get("path", "")
    content = args.get("content", "")
    create_dirs = bool(args.get("createDirs", False))
    overwrite = bool(args.get("overwrite", False))
    abs_path = resolve_path(path)
    if os.path.exists(abs_path) and not overwrite:
        return {"ok": False, "message": "File exists. Set overwrite=true to replace.", "path": os.path.relpath(abs_path, FS_ROOT)}
    try:
        if create_dirs:
            os.makedirs(os.path.dirname(abs_path), exist_ok=True)
        with open(abs_path, "w", encoding="utf-8") as f:
            f.write(content)
        return {"ok": True, "path": os.path.relpath(abs_path, FS_ROOT), "bytesWritten": len(content.encode("utf-8"))}
    except Exception as e:
        return {"ok": False, "message": f"Write error: {e}"}


def handle_fs_delete(args: Dict[str, Any]) -> Dict[str, Any]:
    import shutil
    path = args.get("path", "")
    recursive = bool(args.get("recursive", False))
    abs_path = resolve_path(path)
    if not os.path.exists(abs_path):
        return {"ok": True, "message": "Nothing to delete", "path": os.path.relpath(abs_path, FS_ROOT)}
    try:
        if os.path.isdir(abs_path):
            if recursive:
                shutil.rmtree(abs_path)
            else:
                # ensure empty
                if os.listdir(abs_path):
                    return {"ok": False, "message": "Directory not empty. Use recursive=true.", "path": os.path.relpath(abs_path, FS_ROOT)}
                os.rmdir(abs_path)
        else:
            os.remove(abs_path)
        return {"ok": True, "message": "Deleted", "path": os.path.relpath(abs_path, FS_ROOT)}
    except Exception as e:
        return {"ok": False, "message": f"Delete error: {e}"}


METHODS = {
    "initialize": handle_initialize,
    "tools/list": handle_tools_list,
}

TOOL_HANDLERS = {
    "fs_list": handle_fs_list,
    "fs_read": handle_fs_read,
    "fs_write": handle_fs_write,
    "fs_delete": handle_fs_delete,
}


def handle_tools_call(req: Dict[str, Any]) -> Dict[str, Any]:
    params = req.get("params") or {}
    name = params.get("name")
    args = params.get("arguments") or {}
    if not name:
        return {"ok": False, "error": {"code": -32602, "message": "Missing tool name"}}
    handler = TOOL_HANDLERS.get(name)
    if not handler:
        return {"ok": False, "error": {"code": -32601, "message": "Tool not found"}}
    import time
    t0 = time.time()
    log("tools/call start", tool=name, args=args)
    try:
        res = handler(args)
        dt = int((time.time() - t0) * 1000)
        log("tools/call done", tool=name, durationMs=dt, ok=res.get("ok"))
    except Exception as e:
        dt = int((time.time() - t0) * 1000)
        log("tools/call error", tool=name, durationMs=dt, error=str(e))
        raise
    return {"ok": True, "result": res}

METHODS["tools/call"] = handle_tools_call


def respond(obj: Dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main() -> None:
    log("FS MCP Server starting", FS_ROOT=FS_ROOT, version=VERSION)
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            method = (req.get("method") or "").strip()
            id_ = req.get("id")
            log("request", id=id_, method=method)
            if method in METHODS:
                result = METHODS[method](req)
                respond({"jsonrpc": "2.0", "id": id_, "result": result})
            else:
                respond({"jsonrpc": "2.0", "id": id_, "error": {"code": -32601, "message": "Method not found"}})
        except Exception as e:
            tb = traceback.format_exc()
            respond({"jsonrpc": "2.0", "id": None, "error": {"code": -32000, "message": str(e), "data": tb}})


if __name__ == "__main__":
    main()
