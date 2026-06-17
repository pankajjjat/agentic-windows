#!/usr/bin/env python3
"""
Agentic Windows — Dashboard Backend Server
Zero-dependency Python HTTP server that:
  • Serves the dashboard static files
  • Provides /api/system with live system stats (CPU, RAM, disk, processes)
  • Provides /api/chat for agent interaction via Hermes CLI
"""

import json
import os
import re
import shlex
import subprocess
import sys
import time
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

# ──────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────
PORT = int(os.environ.get("DASHBOARD_PORT", "4774"))
STATIC_DIR = Path(__file__).parent
HERMES_CMD = "hermes"  # Assumes hermes is on PATH (Hermes installs it)

# ──────────────────────────────────────────────
# System Info via PowerShell (built-in, no psutil)
# ──────────────────────────────────────────────

def run_powershell(script):
    """Run a PowerShell script and return stdout."""
    try:
        result = subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
            capture_output=True, text=True, timeout=15, creationflags=subprocess.CREATE_NO_WINDOW
        )
        return result.stdout.strip()
    except Exception as e:
        return f"Error: {e}"

def get_cpu_usage():
    """Get CPU usage via PowerShell."""
    script = '''
    $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    if ($cpu -eq $null) { $cpu = 0 }
    [math]::Round($cpu, 1)
    '''
    try:
        val = run_powershell(script)
        return float(val) if val and val != "Error" else 0.0
    except:
        return 0.0

def get_memory_info():
    """Get memory usage."""
    script = '''
    $os = Get-CimInstance Win32_OperatingSystem
    $total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $free = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $used = [math]::Round($total - $free, 1)
    $pct = [math]::Round(($used / $total) * 100, 1)
    Write-Output "$used|$total|$pct"
    '''
    try:
        val = run_powershell(script)
        if val and "|" in val:
            parts = val.split("|")
            return {
                "usedGB": float(parts[0]),
                "totalGB": float(parts[1]),
                "pct": float(parts[2])
            }
    except:
        pass
    return {"usedGB": 0, "totalGB": 16, "pct": 0}

def get_disk_info():
    """Get C: drive disk usage."""
    script = '''
    $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $total = [math]::Round($drive.Size / 1GB, 1)
    $free = [math]::Round($drive.FreeSpace / 1GB, 1)
    $used = [math]::Round($total - $free, 1)
    $pct = [math]::Round(($used / $total) * 100, 1)
    Write-Output "$used|$free|$total|$pct"
    '''
    try:
        val = run_powershell(script)
        if val and "|" in val:
            parts = val.split("|")
            return {
                "usedGB": float(parts[0]),
                "freeGB": float(parts[1]),
                "totalGB": float(parts[2]),
                "pct": float(parts[3])
            }
    except:
        pass
    return {"usedGB": 0, "freeGB": 0, "totalGB": 0, "pct": 0}

def get_uptime():
    """Get system uptime as a human string."""
    script = '''
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $uptime = (Get-Date) - $boot
    $days = $uptime.Days
    $hours = $uptime.Hours
    $mins = $uptime.Minutes
    Write-Output "$days d $hours h $mins m"
    '''
    try:
        return run_powershell(script) or "Unknown"
    except:
        return "Unknown"

def get_processes():
    """Get top processes by memory usage."""
    script = '''
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 30 |
    ForEach-Object { Write-Output "$($_.Id)|$($_.ProcessName)|$([math]::Round($_.WorkingSet64 / 1MB, 1))|0.0" }
    '''
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
                            "cpu": 0.0
                        })
        return processes
    except:
        return []

def get_agent_status():
    """Check if Hermes agent is running."""
    try:
        result = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq hermes.exe", "/FO", "CSV", "/NH"],
            capture_output=True, text=True, timeout=5, creationflags=subprocess.CREATE_NO_WINDOW
        )
        if "hermes.exe" in result.stdout:
            return "Agent Online"
    except:
        pass
    return "Agent Offline"

def collect_system_info():
    """Collect all system info in one call."""
    return {
        "cpu": get_cpu_usage(),
        "memory": get_memory_info(),
        "disk": get_disk_info(),
        "uptime": get_uptime(),
        "processes": get_processes(),
        "agentStatus": get_agent_status()
    }

# ──────────────────────────────────────────────
# Hermes Chat Interface
# ──────────────────────────────────────────────

def chat_with_hermes(message):
    """Send a message to Hermes and get the response."""
    try:
        # Use a temp PowerShell wrapper that pipes the message into hermes
        escaped = message.replace("'", "''")
        ps_cmd = f'''
$msg = '{escaped}'
try {{
    $result = $msg | & hermes run 2>&1
    Write-Output $result
}} catch {{
    Write-Error $_.Exception.Message
}}
'''
        result = subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command", ps_cmd],
            capture_output=True, text=True, timeout=120,
            creationflags=subprocess.CREATE_NO_WINDOW
        )

        response = result.stdout.strip() or result.stderr.strip() or "No response from agent."
        return {
            "response": response,
            "exitCode": result.returncode,
            "commands": extract_commands(response)
        }
    except subprocess.TimeoutExpired:
        return {"response": "⏱️ Agent timed out after 120 seconds.", "commands": []}
    except FileNotFoundError:
        return {"response": "❌ Hermes not found. Install Hermes first: https://hermes-agent.nousresearch.com/docs", "commands": []}
    except Exception as e:
        return {"response": f"❌ Error: {str(e)}", "commands": []}

def extract_commands(text):
    """Extract actionable commands from agent response."""
    commands = []
    # Look for patterns like `hermes run skill X` or `winget install X`
    skill_match = re.findall(r'hermes\s+run\s+skill\s+(\S+)', text, re.IGNORECASE)
    for s in skill_match:
        commands.append({"type": "skill", "name": s})
    return commands

# ──────────────────────────────────────────────
# HTTP Request Handler
# ──────────────────────────────────────────────

class DashboardHandler(BaseHTTPRequestHandler):
    """Handles dashboard API + static file serving."""

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/index.html"

        # ── API endpoint: System info ──
        if path == "/api/system":
            return self._json_response(collect_system_info())

        # ── Static files ──
        file_path = STATIC_DIR / path.lstrip("/")
        if not file_path.exists():
            file_path = STATIC_DIR / "index.html"

        if file_path.exists():
            ext = file_path.suffix.lower()
            content_type = {
                ".html": "text/html",
                ".js": "application/javascript",
                ".css": "text/css",
                ".json": "application/json",
                ".png": "image/png",
                ".svg": "image/svg+xml",
                ".ico": "image/x-icon",
            }.get(ext, "application/octet-stream")

            try:
                with open(file_path, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", f"{content_type}; charset=utf-8")
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

        # ── API endpoint: Chat ──
        if parsed.path == "/api/chat":
            content_len = int(self.headers.get("Content-Length", 0))
            if content_len == 0:
                return self._json_response({"error": "Empty request"}, 400)

            try:
                body = json.loads(self.rfile.read(content_len))
                message = body.get("message", "").strip()
                if not message:
                    return self._json_response({"error": "Message is required"}, 400)

                result = chat_with_hermes(message)
                return self._json_response(result)
            except json.JSONDecodeError:
                return self._json_response({"error": "Invalid JSON"}, 400)

        self._json_response({"error": "Not found"}, 404)

    def _json_response(self, data, status=200):
        """Send a JSON response."""
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        """Quiet logging — only log API calls, not static files."""
        if "/api/" in str(args[0]):
            print(f"[{time.strftime('%H:%M:%S')}] {args[0]}", flush=True)

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────

def main():
    print(f"""
  ╔══════════════════════════════════════╗
  ║   ⚡ Agentic Windows Dashboard       ║
  ║   http://localhost:{PORT}             ║
  ╚══════════════════════════════════════╝

  Press Ctrl+C to stop.
""", flush=True)

    server = HTTPServer(("127.0.0.1", PORT), DashboardHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  Shutting down...")
        server.server_close()

if __name__ == "__main__":
    main()
