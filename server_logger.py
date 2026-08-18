#!/usr/bin/env python3
import http.server
import socketserver
import socket
import threading
import json
import time
import os
import sys

HTTP_PORT = 8080
UDP_PORT = 8080
LOG_FILE = "/home/admin/mythic/live_logs.txt"

# Clear or initialize log file
with open(LOG_FILE, "a") as f:
    f.write(f"\n\n=== LOG SESSION STARTED AT {time.strftime('%Y-%m-%d %H:%M:%S')} ===\n")

COMMAND_QUEUE = []
COMMAND_LOCK = threading.Lock()

def write_log(source, message):
    timestamp = time.strftime("%H:%M:%S")
    formatted = f"[{timestamp}] [{source}] {message.strip()}"
    print(formatted, flush=True)
    with open(LOG_FILE, "a") as f:
        f.write(formatted + "\n")

class LogHTTPHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/status" or self.path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(b'{"status": "online", "service": "iWin Remote Log Server"}')
        elif self.path == "/logs":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            if os.path.exists(LOG_FILE):
                with open(LOG_FILE, "rb") as f:
                    self.wfile.write(f.read())
            else:
                self.wfile.write(b"No logs yet.")
        elif self.path == "/api/patch/manifest" or self.path == "/patch/manifest":
            patch_dir = "/home/admin/mythic/patch_repo"
            os.makedirs(patch_dir, exist_ok=True)
            files = []
            for root, _, filenames in os.walk(patch_dir):
                for fn in filenames:
                    fp = os.path.join(root, fn)
                    rel = os.path.relpath(fp, patch_dir)
                    files.append({
                        "name": rel,
                        "size": os.path.getsize(fp),
                        "mtime": int(os.path.getmtime(fp))
                    })
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps({"version": int(time.time()), "files": files}).encode("utf-8"))
        elif self.path.startswith("/api/patch/download/") or self.path.startswith("/patch/download/"):
            rel_path = self.path.split("/download/", 1)[1]
            patch_dir = "/home/admin/mythic/patch_repo"
            file_path = os.path.normpath(os.path.join(patch_dir, rel_path))
            if file_path.startswith(patch_dir) and os.path.isfile(file_path):
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Content-Length", str(os.path.getsize(file_path)))
                self.end_headers()
                with open(file_path, "rb") as f:
                    self.wfile.write(f.read())
            else:
                self.send_response(404)
                self.end_headers()
        elif self.path.startswith("/api/command/poll"):
            with COMMAND_LOCK:
                if COMMAND_QUEUE:
                    cmd = COMMAND_QUEUE.pop(0)
                else:
                    cmd = {"cmd": "none"}
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(cmd).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def do_HEAD(self):
        if self.path.startswith("/api/patch/manifest") or self.path.startswith("/patch/manifest"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
        elif self.path.startswith("/api/patch/download/") or self.path.startswith("/patch/download/"):
            rel_path = self.path.split("/download/", 1)[1]
            patch_dir = "/home/admin/mythic/patch_repo"
            file_path = os.path.normpath(os.path.join(patch_dir, rel_path))
            if file_path.startswith(patch_dir) and os.path.isfile(file_path):
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Content-Length", str(os.path.getsize(file_path)))
                self.end_headers()
            else:
                self.send_response(404)
                self.end_headers()
        else:
            self.send_response(200)
            self.end_headers()

    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length).decode('utf-8', errors='replace')
        
        if self.path == "/api/command/send":
            try:
                cmd_data = json.loads(body)
                with COMMAND_LOCK:
                    COMMAND_QUEUE.append(cmd_data)
                write_log("COMMAND/QUEUED", f"Command queued: {cmd_data}")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(b'{"status": "queued"}')
            except Exception as e:
                self.send_response(400)
                self.end_headers()
            return
        elif self.path == "/api/command/ack":
            try:
                ack_data = json.loads(body)
                write_log("COMMAND/ACK", f"Result from iPad: {ack_data}")
            except Exception:
                write_log("COMMAND/ACK", body)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(b'{"status": "received"}')
            return

        try:
            data = json.loads(body)
            msg = data.get("message") or data.get("log") or body
            level = data.get("level", "INFO")
            write_log(f"HTTP/{level}", msg)
        except Exception:
            write_log("HTTP/RAW", body)
            
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(b'{"status": "ok"}')

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def log_message(self, format, *args):
        # Suppress standard HTTP request spam in terminal
        pass

def run_udp_server():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", UDP_PORT))
    print(f"[*] UDP Log Server listening on 0.0.0.0:{UDP_PORT}", flush=True)
    while True:
        try:
            data, addr = sock.recvfrom(65535)
            msg = data.decode('utf-8', errors='replace')
            write_log(f"UDP/{addr[0]}", msg)
        except Exception as e:
            print(f"[UDP Error] {e}", flush=True)

def main():
    print(f"[*] Starting iWin Real-Time Remote Log Server...")
    print(f"[*] Public IP: 3.1.51.240")
    print(f"[*] HTTP endpoint: http://3.1.51.240:{HTTP_PORT}/log")
    print(f"[*] UDP endpoint: 3.1.51.240:{UDP_PORT}")
    print(f"[*] Log file: {LOG_FILE}\n", flush=True)

    # Start UDP listener in thread
    udp_thread = threading.Thread(target=run_udp_server, daemon=True)
    udp_thread.start()

    # Start HTTP listener
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("0.0.0.0", HTTP_PORT), LogHTTPHandler) as httpd:
        print(f"[*] HTTP Log Server listening on 0.0.0.0:{HTTP_PORT}", flush=True)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server.")

if __name__ == "__main__":
    main()
