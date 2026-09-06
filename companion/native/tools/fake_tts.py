#!/usr/bin/env python3
"""FAKE GPT-SoVITS endpoint for native protocol probes (TEST ONLY, no model).

Answers POST /tts with streaming raw signed-16 LE mono 32000 Hz PCM (a soft tone whose
length grows with the text) in 1280-byte blocks, exactly the shape stream_pipeline.py
consumes with media_type=raw + streaming_mode. GET / returns 200 for health checks.

Usage: fake_tts.py [port]   (default 9881)
"""
import json
import math
import struct
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RATE = 32000


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # quiet
        pass

    def do_GET(self):
        body = b'{"ok": true, "fake_tts": true}'
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path.split('?')[0] != '/tts':
            self.send_response(404)
            self.end_headers()
            return
        length = int(self.headers.get('Content-Length') or 0)
        try:
            payload = json.loads(self.rfile.read(length) or b'{}')
        except ValueError:
            payload = {}
        text = str(payload.get('text', ''))
        seconds = min(2.0, max(0.3, 0.07 * len(text)))
        frames = int(seconds * RATE)
        pcm = bytearray()
        for i in range(frames):
            env = min(1.0, i / 800.0, (frames - i) / 800.0)
            pcm += struct.pack('<h', int(9000 * env * math.sin(2 * math.pi * 220.0 * i / RATE)))
        self.send_response(200)
        self.send_header('Content-Type', 'audio/raw')
        self.send_header('Transfer-Encoding', 'chunked')
        self.end_headers()
        for off in range(0, len(pcm), 1280):
            block = bytes(pcm[off:off + 1280])
            self.wfile.write(b'%x\r\n%s\r\n' % (len(block), block))
            self.wfile.flush()
            time.sleep(0.004)
        self.wfile.write(b'0\r\n\r\n')
        self.wfile.flush()


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9881
    ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
