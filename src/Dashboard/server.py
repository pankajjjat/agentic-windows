#!/usr/bin/env python3
"""
Agentic Windows — Dashboard Backend Server
Zero-dependency Python HTTP server that:
  • Serves dashboard static files
  • Provides /api/system with live system stats (CPU, RAM, disk, processes)
  • Provides /api/chat with Server-Sent Events (SSE) streaming
  • Provides /api/chat (POST) for backward-compatible synchronous chat
"""

import json
import os
import re
import socketserver
import subprocess
import sys
import time
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from threading import Thread

# ── Configuration ──
PORT = int(os.environ.get("DASHBOARD_PORT", "4774"))
STATIC_DIR = Path(__file__).parent
HERMES_CMD = "hermes"  # Must be on PATH
CHAT_TIMEOUT = 300      # 5 minutes max for long agent tasks


# ══════════════════════════════════════════════
# System Info via PowerShell
# ══════════════════════════════════════════════

def run_powershell(script):
    """Run a PowerShell script and return stdout."""
    try:
        result = subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
            capture_output=True, text=True, timeout=15,
            creationflags=subprocess.CREATE_NO_WINDOW
        )
        return result.stdout.strip()
    except:
        return ""


def get_cpu_usage():
    script = (
        '$cpu = (Get-CimInstance Win32_Processor | '
        'Measure-Object -Property LoadPercentage -Average).Average; '
        'if ($cpu -eq $null) { $cpu = 0 }; [math]::Round($cpu, 1)'
    )
    try:
        val = run_powershell(script)
        return float(val) if val else 0.0
    except:
        return 0.0


def get_memory_info():
    script = (
        '$os = Get-CimInstance Win32_OperatingSystem; '
        '$total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1); '
        '$free = [math]::Round($os.FreePhysicalMemory / 1MB, 1); '
        '$used = [math]::Round($total - $free, 1); '
        '$pct = [math]::Round(($used / $total) * 100, 1); '
        'Write-Output "$used|$total|$pct"'
    )
    try:
        val = run_powershell(script)
        if val and "|" in val:
            parts = val.split("|")
            return {"usedGB": float(parts[0]), "totalGB": float(parts[1]),
                    "pct": float(parts[2])}
    except:
        pass
    return {"usedGB": 0, "totalGB": 16, "pct": 0}


def get_disk_info():
    script = (
        '$drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID=\'C:\'"; '
        '$total = [math]::Round($drive.Size / 1GB, 1); '
        '$free = [math]::Round($drive.FreeSpace / 1GB, 1); '
        '$used = [math]::Round($total - $free, 1); '
        '$pct = [math]::Round(($used / $total) * 100, 1); '
        'Write-Output "$used|$free|$total|$pct"'
    )
    try:
        val = run_powershell(script)
        if val and "|" in val:
            parts = val.split("|")
            return {"usedGB": float(parts[0]), "freeGB": float(parts[1]),
                    "totalGB": float(parts[2]), "pct": float(parts[3])}
    except:
        pass
    return {"usedGB": 0, "freeGB": 0, "totalGB": 0, "pct": 0}


def get_uptime():
    script = (
        '$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime; '
        '$uptime = (Get-Date) - $boot; '
        'Write-Output "$($uptime.Days) d $($uptime.Hours) h $($uptime.Minutes) m"'
    )
    try:
        return run_powershell(script) or "Unknown"
    except:
        return "Unknown"


def get_processes():
    script = (
        'Get-Process | Sort-Object WorkingSet64 -Descending | '
        'Select-Object -First 30 | '
        'ForEach-Object { '
        'Write-Output "$($_.Id)|$($_.ProcessName)|'
        '$([math]::Round($_.WorkingSet64 / 1MB, 1))|0.0" }'
    )
    try:
        val = run_powershell(script)
        processes = []
        if val:
            for line in val.split("\n"):
                line = line.strip()
                if "|" in line:
                    parts = line.split("|")
                    if len(parts) >= 3:
                        processes.append({
                            "pid": int(parts[0]),
                            "name": parts[1],
                            "memoryMB": float(parts[2]),
                            "cpu": 0.0,
                        })
        return processes
    except:
        return []


def get_agent_status():
    try:
        result = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq hermes.exe", "/FO", "CSV", "/NH"],
            capture_output=True, text=True, timeout=5,
            creationflags=subprocess.CREATE_NO_WINDOW
        )
        return "Agent Online" if "hermes.exe" in result.stdout else "Agent Offline"
    except:
        return "Agent Offline"


def collect_system_info():
    return {
        "cpu": get_cpu_usage(),
        "memory": get_memory_info(),
        "disk": get_disk_info(),
        "uptime": get_uptime(),
        "processes": get_processes(),
        "agentStatus": get_agent_status(),
    }


# ══════════════════════════════════════════════
# Hermes Chat — Synchronous (fallback)
# ══════════════════════════════════════════════

def chat_with_hermes(message):
    """Send a message to Hermes and return the full response."""
    try:
        escaped = message.replace("'", "''")
        ps_cmd = (
            f"$msg = '{escaped}'\n"
            f"try {{ $result = $msg | & {HERMES_CMD} run 2>&1; "
            f"Write-Output $result }} "
            f"catch {{ Write-Error $_.Exception.Message }}"
        )
        result = subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command", ps_cmd],
            capture_output=True, text=True, timeout=CHAT_TIMEOUT,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
        response = result.stdout.strip() or result.stderr.strip() or "No response."
        return {"response": response, "exitCode": result.returncode,
                "commands": extract_commands(response)}
    except subprocess.TimeoutExpired:
        return {"response": "⏱️ Agent timed out after 300 seconds.", "commands": []}
    except FileNotFoundError:
        return {"response": "❌ Hermes not found.", "commands": []}
    except Exception as e:
        return {"response": f"❌ Error: {e}", "commands": []}


# ══════════════════════════════════════════════
# Hermes Chat — Streaming (SSE)
# ══════════════════════════════════════════════

def stream_hermes_to_client(message, wfile):
    """Stream Hermes response to wfile as SSE events."""
    try:
        wfile.write(b"data: " + json.dumps({"type": "start"}).encode() + b"\n\n")
        wfile.flush()

        escaped = message.replace("'", "''")
        ps_cmd = (
            f"$msg = '{escaped}'\n"
            f"try {{ $result = $msg | & {HERMES_CMD} run 2>&1; "
            f"Write-Output $result }} "
            f"catch {{ Write-Error $_.Exception.Message }}"
        )

        proc = subprocess.Popen(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command", ps_cmd],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )

        full_text = ""
        for line in iter(proc.stdout.readline, ""):
            if line:
                chunk = line.rstrip("\r\n")
                full_text += chunk + "\n"
                event = json.dumps({"type": "token", "text": chunk})
                wfile.write(f"data: {event}\n\n".encode())
                wfile.flush()

        proc.wait(timeout=10)
        wfile.write(b"data: " + json.dumps({
            "type": "done",
            "commands": extract_commands(full_text),
        }).encode() + b"\n\n")
        wfile.flush()

    except subprocess.TimeoutExpired:
        wfile.write(b"data: " + json.dumps(
            {"type": "error", "text": "⏱️ Agent timed out."}).encode() + b"\n\n")
        wfile.flush()
        proc.kill()
    except FileNotFoundError:
        wfile.write(b"data: " + json.dumps(
            {"type": "error", "text": "❌ Hermes not found."}).encode() + b"\n\n")
        wfile.flush()
    except Exception as e:
        wfile.write(b"data: " + json.dumps(
            {"type": "error", "text": f"❌ {e}"}).encode() + b"\n\n")
        wfile.flush()
    finally:
        try:
            wfile.write(b"data: [DONE]\n\n")
            wfile.flush()
        except:
            pass


def extract_commands(text):
    """Extract actionable commands from agent response."""
    commands = []
    skills = re.findall(r"hermes\s+run\s+skill\s+(\S+)", text, re.IGNORECASE)
    for s in skills:
        commands.append({"type": "skill", "name": s})
    return commands


# ══════════════════════════════════════════════
# HTTP Request Handler
# ══════════════════════════════════════════════

CONTENT_TYPES = {
    ".html": "text/html", ".js": "application/javascript",
    ".css": "text/css", ".json": "application/json",
    ".png": "image/png", ".svg": "image/svg+xml",
    ".ico": "image/x-icon",
}


class DashboardHandler(BaseHTTPRequestHandler):

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/index.html"

        # ── SSE: Streaming chat ──
        if path == "/api/chat/stream":
            params = urllib.parse.parse_qs(parsed.query)
            message = params.get("message", [""])[0].strip()
            if not message:
                return self._json_response({"error": "Message is required"}, 400)
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            stream_hermes_to_client(message, self.wfile)
            return

        # ── API: System info ──
        if path == "/api/system":
            return self._json_response(collect_system_info())

        # ── Static files ──
        file_path = (STATIC_DIR / path.lstrip("/"))
        if not file_path.exists() or not file_path.is_file():
            file_path = STATIC_DIR / "index.html"
        if file_path.exists():
            ext = file_path.suffix.lower()
            ctype = CONTENT_TYPES.get(ext, "application/octet-stream")
            try:
                data = file_path.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", f"{ctype}; charset=utf-8")
                self.send_header("Content-Length", len(data))
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                self.wfile.write(data)
            except Exception:
                self._json_response({"error": "File read error"}, 500)
        else:
            self._json_response({"error": "Not found"}, 404)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)

        # ── API: Synchronous chat (fallback) ──
        if parsed.path == "/api/chat":
            content_len = int(self.headers.get("Content-Length", 0))
            if content_len == 0:
                return self._json_response({"error": "Empty request"}, 400)
            try:
                body = json.loads(self.rfile.read(content_len))
                message = body.get("message", "").strip()
                if not message:
                    return self._json_response({"error": "Message is required"}, 400)
                return self._json_response(chat_with_hermes(message))
            except json.JSONDecodeError:
                return self._json_response({"error": "Invalid JSON"}, 400)

        self._json_response({"error": "Not found"}, 404)

    # ── CORS preflight ──
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def _json_response(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        if "/api/" in str(args[0]):
            print(f"[{time.strftime('%H:%M:%S')}] {args[0]}", flush=True)


# ── Threading mixin for concurrent connections (SSE won't block polling) ──
class ThreadingDashboardServer(socketserver.ThreadingMixIn, HTTPServer):
    allow_reuse_address = True
    daemon_threads = True


# ══════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════

def main():
    print(f"""
  ╔══════════════════════════════════════╗
  ║   ⚡ Agentic Windows Dashboard       ║
  ║   http://localhost:{PORT}             ║
  ║                                      ║
  ║   SSE streaming  •  Threaded server  ║
  ╚══════════════════════════════════════╝

  Press Ctrl+C to stop.
""", flush=True)

    server = ThreadingDashboardServer(("127.0.0.1", PORT), DashboardHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  Shutting down...")
        server.server_close()


if __name__ == "__main__":
    main()
