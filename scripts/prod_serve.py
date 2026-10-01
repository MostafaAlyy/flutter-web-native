#!/usr/bin/env python3
"""Prod-like static server for A/B-measuring Flutter web builds.

`python -m http.server` serves uncompressed bytes with no cache policy, which
massively overstates download time for .wasm/.js. This server:

  - negotiates br (if the `brotli` module is installed) or gzip from Accept-Encoding,
    caches compressed bodies, and sends Vary: Accept-Encoding
  - sends `immutable` for content-hashed names (foo.<8+ hex>.ext), `no-cache` for
    index.html / flutter_bootstrap.js / flutter_service_worker.js / unhashed
    entrypoints, and a short TTL for everything else
  - SPA fallback: extension-less paths serve index.html; missing files WITH an
    extension get 404 (pass --spa-fallback-all to mimic hosts that answer every
    miss with HTML, e.g. to reproduce Lighthouse valid-source-maps failures)
  - optional --coop-coep to test multithreaded Skwasm (cross-origin isolation)

Usage: prod_serve.py BUILD_DIR [PORT] [--spa-fallback-all] [--coop-coep]
"""
import argparse
import gzip
import http.server
import mimetypes
import os
import re

try:
    import brotli  # pip install brotli
except ImportError:
    brotli = None

COMPRESSIBLE = ('.js', '.mjs', '.wasm', '.json', '.html', '.css', '.ttf', '.otf', '.svg', '.txt', '.map')
NO_CACHE = {'index.html', 'flutter_bootstrap.js', 'flutter_service_worker.js', 'flutter.js', 'version.json'}
HASHED = re.compile(r'\.[0-9a-f]{8,}\.[A-Za-z0-9]+$')

mimetypes.add_type('application/wasm', '.wasm')
mimetypes.add_type('text/javascript', '.mjs')
mimetypes.add_type('text/javascript', '.js')


def make_handler(root, spa_all, coop_coep):
    cache = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, *args):
            pass

        def _resolve(self):
            path = self.path.split('?', 1)[0].split('#', 1)[0]
            rel = os.path.normpath(path.lstrip('/')) if path not in ('', '/') else 'index.html'
            if rel.startswith('..'):
                return None
            fs = os.path.join(root, rel)
            if os.path.isdir(fs):
                fs = os.path.join(fs, 'index.html')
            if os.path.isfile(fs):
                return fs
            has_ext = '.' in os.path.basename(rel)
            if has_ext and not spa_all:
                return None
            return os.path.join(root, 'index.html')

        def _body(self, fs, accept):
            enc = None
            if fs.endswith(COMPRESSIBLE):
                if brotli and 'br' in accept:
                    enc = 'br'
                elif 'gzip' in accept:
                    enc = 'gzip'
            key = (fs, enc, os.path.getmtime(fs))
            if key not in cache:
                with open(fs, 'rb') as fh:
                    data = fh.read()
                if enc == 'br':
                    data = brotli.compress(data, quality=9)
                elif enc == 'gzip':
                    data = gzip.compress(data, compresslevel=9)
                cache[key] = data
            return cache[key], enc

        def _cache_control(self, fs):
            name = os.path.basename(fs)
            if name in NO_CACHE or (name.startswith('main.dart.') and not HASHED.search(name)):
                return 'no-cache'
            if HASHED.search(name):
                return 'public, max-age=31536000, immutable'
            return 'public, max-age=3600'

        def _serve(self, head_only=False):
            fs = self._resolve()
            if not fs or not os.path.isfile(fs):
                self.send_response(404)
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
            data, enc = self._body(fs, self.headers.get('Accept-Encoding', ''))
            self.send_response(200)
            self.send_header('Content-Type', mimetypes.guess_type(fs)[0] or 'application/octet-stream')
            if enc:
                self.send_header('Content-Encoding', enc)
            self.send_header('Vary', 'Accept-Encoding')
            self.send_header('Cache-Control', self._cache_control(fs))
            if coop_coep:
                self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
                self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            if not head_only:
                self.wfile.write(data)

        def do_GET(self):
            self._serve()

        def do_HEAD(self):
            self._serve(head_only=True)

    return Handler


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('root')
    ap.add_argument('port', nargs='?', type=int, default=8080)
    ap.add_argument('--host', default='127.0.0.1')
    ap.add_argument('--spa-fallback-all', action='store_true')
    ap.add_argument('--coop-coep', action='store_true')
    args = ap.parse_args()
    root = os.path.abspath(args.root)
    if not os.path.isfile(os.path.join(root, 'index.html')):
        raise SystemExit(f'{root} has no index.html — pass a `flutter build web -o` directory')
    print(f'serving {root} on http://{args.host}:{args.port} '
          f'(compression: {"br+gzip" if brotli else "gzip only — pip install brotli"})')
    http.server.ThreadingHTTPServer((args.host, args.port),
                                    make_handler(root, args.spa_fallback_all, args.coop_coep)).serve_forever()


if __name__ == '__main__':
    main()
