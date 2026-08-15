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
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length).decode('utf-8', errors='replace')
        
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
    class ReusableTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

    with ReusableTCPServer(("0.0.0.0", HTTP_PORT), LogHTTPHandler) as httpd:
        print(f"[*] HTTP Log Server listening on 0.0.0.0:{HTTP_PORT}", flush=True)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server.")

if __name__ == "__main__":
    main()
