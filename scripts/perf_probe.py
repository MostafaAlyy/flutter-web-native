#!/usr/bin/env python3
"""Flutter web performance probe over the Chrome DevTools Protocol.

Launches a fresh headless Chrome (SwiftShader, cold cache) per run and reports
GPU-independent metrics — the ones that still discriminate when the headless
GPU is software (rAF fps there is meaningless; see
references/performance-measurement.md):

  ttff_ms                 navigation -> `flutter-first-frame` window event
  idle.main_ms_per_frame  TaskDuration delta / rAF callbacks over an idle window
  idle.main_busy_pct      TaskDuration delta / wall time
  scroll.*                same, during wheel (desktop) or touch-fling (mobile) scroll
  *.loaf_blocking_ms      sum of long-animation-frame blockingDuration
  transfer_kb, top        bytes on the wire incl. Web Worker requests (auto-attach)

Usage:
  perf_probe.py URL [--profile desktop|mobile|tablet] [--runs 3] [--reduced-motion]
                    [--cpu N] [--settle 15] [--idle 5] [--scroll auto|wheel|touch|none]
                    [--out result.json] [--chrome PATH] [--port 9555]

Never run two probes (or a probe and a build) at the same time: CPU contention
corrupts both. Requires: pip install websocket-client
"""
import argparse
import json
import os
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import time
import urllib.request

try:
    import websocket  # websocket-client
except ImportError:
    sys.exit('perf_probe.py needs websocket-client: pip install websocket-client')

PROFILES = {
    'desktop': dict(w=1440, h=900, dpr=1, mobile=False, cpu=1),
    'mobile': dict(w=412, h=823, dpr=2.625, mobile=True, cpu=4),
    'tablet': dict(w=820, h=1180, dpr=2, mobile=True, cpu=2),
}

INJECT = r'''
window.__pp = {ff: null, frames: [], loaf: []};
addEventListener('flutter-first-frame', () => { window.__pp.ff = performance.now(); });
try {
  new PerformanceObserver(l => { for (const e of l.getEntries())
    window.__pp.loaf.push([e.startTime, e.duration, e.blockingDuration || 0]); })
    .observe({type: 'long-animation-frame', buffered: true});
} catch (e) {}
(function raf(t) {
  const f = window.__pp.frames; f.push(t);
  if (f.length > 20000) f.splice(0, 10000);
  requestAnimationFrame(raf);
})(0);
'''


def find_chrome(explicit):
    for c in [explicit, os.environ.get('CHROME'), 'google-chrome-stable', 'google-chrome',
              'chromium', 'chromium-browser',
              '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome']:
        if c and (shutil.which(c) or os.path.exists(c)):
            return shutil.which(c) or c
    sys.exit('Chrome not found; pass --chrome PATH or set CHROME')


class Cdp:
    def __init__(self, ws_url):
        self.ws = websocket.create_connection(ws_url, suppress_origin=True, max_size=None)
        self.ws.settimeout(1)
        self.next_id = 0
        self.events = []

    def _handle(self, msg):
        self.events.append(msg)
        # Worker requests never reach the page target's Network domain.
        if msg.get('method') == 'Target.attachedToTarget':
            sid = msg['params']['sessionId']
            if msg['params']['targetInfo'].get('type') in ('worker', 'shared_worker', 'service_worker'):
                self.send('Network.enable', session=sid, wait=False)
            self.send('Runtime.runIfWaitingForDebugger', session=sid, wait=False)

    def send(self, method, params=None, session=None, wait=True, timeout=60):
        self.next_id += 1
        mid = self.next_id
        msg = {'id': mid, 'method': method, 'params': params or {}}
        if session:
            msg['sessionId'] = session
        self.ws.send(json.dumps(msg))
        if not wait:
            return None
        end = time.time() + timeout
        while time.time() < end:
            try:
                m = json.loads(self.ws.recv())
            except websocket.WebSocketTimeoutException:
                continue
            if m.get('id') == mid:
                if 'error' in m:
                    raise RuntimeError(f'{method}: {m["error"]}')
                return m.get('result', {})
            self._handle(m)
        raise TimeoutError(method)

    def pump(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            try:
                self._handle(json.loads(self.ws.recv()))
            except websocket.WebSocketTimeoutException:
                pass

    def eval(self, expr):
        r = self.send('Runtime.evaluate', {'expression': expr, 'returnByValue': True, 'awaitPromise': True})
        return r.get('result', {}).get('value')

    def metrics(self):
        return {m['name']: m['value'] for m in self.send('Performance.getMetrics')['metrics']}


def window_stats(cdp, t0, t1, m0, m1):
    frames = cdp.eval(f'window.__pp.frames.filter(t => t >= {t0} && t <= {t1}).length') or 0
    loaf = cdp.eval(f'window.__pp.loaf.filter(e => e[0] >= {t0} && e[0] <= {t1})') or []
    secs = max((t1 - t0) / 1000, 1e-6)
    task = m1['TaskDuration'] - m0['TaskDuration']
    return {
        'main_busy_pct': round(100 * task / secs, 1),
        'main_ms_per_frame': round(task * 1000 / max(frames, 1), 2),
        'raf_callbacks': frames,
        'loaf_count': len(loaf),
        'loaf_blocking_ms': round(sum(e[2] for e in loaf)),
    }


def scroll(cdp, prof, mode):
    x, y = prof['w'] // 2, prof['h'] // 2
    if mode == 'touch':
        for _ in range(3):
            cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{'x': x, 'y': y + 250}]})
            for i in range(1, 16):
                cdp.send('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{'x': x, 'y': y + 250 - i * 30}]})
                time.sleep(0.016)
            cdp.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []})
            cdp.pump(0.9)
    else:  # trusted mouse-wheel notches: 28 down, 12 up
        for i in range(40):
            cdp.send('Input.dispatchMouseEvent', {'type': 'mouseWheel', 'x': x, 'y': y,
                                                  'deltaX': 0, 'deltaY': 120 if i < 28 else -120})
            time.sleep(0.07)
        cdp.pump(1.0)


def network_summary(events):
    reqs = {}
    for m in events:
        method, p, sid = m.get('method'), m.get('params', {}), m.get('sessionId', 'page')
        if method == 'Network.responseReceived':
            r = p['response']
            headers = {k.lower(): v for k, v in r.get('headers', {}).items()}
            reqs[(sid, p['requestId'])] = {'url': r['url'], 'bytes': 0, 'worker': sid != 'page',
                                           'enc': headers.get('content-encoding', '')}
        elif method == 'Network.loadingFinished' and (sid, p['requestId']) in reqs:
            reqs[(sid, p['requestId'])]['bytes'] = p.get('encodedDataLength', 0)
    total = sum(r['bytes'] for r in reqs.values())
    top = sorted(reqs.values(), key=lambda r: -r['bytes'])[:12]
    return {
        'requests': len(reqs),
        'worker_requests': sum(1 for r in reqs.values() if r['worker']),
        'transfer_kb': round(total / 1024),
        'top': [f"{round(r['bytes'] / 1024)}KB {r['enc'] or 'identity'}{' [worker]' if r['worker'] else ''} {r['url'][:110]}"
                for r in top],
    }


def run_once(args, prof, chrome_bin):
    udd = tempfile.mkdtemp(prefix='perfprobe-')
    proc = subprocess.Popen([
        chrome_bin, '--headless=new', '--use-gl=angle', '--use-angle=swiftshader',
        '--enable-unsafe-swiftshader', '--no-first-run', '--no-default-browser-check',
        f'--remote-debugging-port={args.port}', '--remote-allow-origins=*',
        f'--user-data-dir={udd}', f'--window-size={prof["w"]},{prof["h"]}', 'about:blank'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        page = None
        for _ in range(100):
            try:
                tabs = json.load(urllib.request.urlopen(f'http://127.0.0.1:{args.port}/json'))
                page = next(t for t in tabs if t['type'] == 'page')
                break
            except Exception:
                time.sleep(0.2)
        if not page:
            raise RuntimeError('Chrome DevTools endpoint did not come up')
        cdp = Cdp(page['webSocketDebuggerUrl'])
        for domain in ('Network', 'Page', 'Runtime', 'Performance'):
            cdp.send(f'{domain}.enable')
        cdp.send('Target.setAutoAttach', {'autoAttach': True, 'waitForDebuggerOnStart': False, 'flatten': True})
        cdp.send('Emulation.setDeviceMetricsOverride', {'width': prof['w'], 'height': prof['h'],
                 'deviceScaleFactor': prof['dpr'], 'mobile': prof['mobile']})
        if prof['mobile']:
            cdp.send('Emulation.setTouchEmulationEnabled', {'enabled': True})
        if args.reduced_motion:
            cdp.send('Emulation.setEmulatedMedia', {'features': [{'name': 'prefers-reduced-motion', 'value': 'reduce'}]})
        if prof['cpu'] > 1:
            cdp.send('Emulation.setCPUThrottlingRate', {'rate': prof['cpu']})
        cdp.send('Page.addScriptToEvaluateOnNewDocument', {'source': INJECT})

        cdp.send('Page.navigate', {'url': args.url})
        ff, deadline = None, time.time() + args.timeout
        while time.time() < deadline and not ff:
            cdp.pump(0.5)
            ff = cdp.eval('window.__pp && window.__pp.ff')
        result = {'ttff_ms': round(ff) if ff else None}
        if not ff:
            print('warning: no flutter-first-frame event (blank page? wrong URL? GL flags?)', file=sys.stderr)
        cdp.pump(args.settle)

        m0, t0 = cdp.metrics(), cdp.eval('performance.now()')
        cdp.pump(args.idle)
        m1, t1 = cdp.metrics(), cdp.eval('performance.now()')
        result['idle'] = window_stats(cdp, t0, t1, m0, m1)

        mode = args.scroll if args.scroll != 'auto' else ('touch' if prof['mobile'] else 'wheel')
        if mode != 'none':
            m0, t0 = cdp.metrics(), cdp.eval('performance.now()')
            scroll(cdp, prof, mode)
            m1, t1 = cdp.metrics(), cdp.eval('performance.now()')
            result['scroll'] = dict(window_stats(cdp, t0, t1, m0, m1), mode=mode)

        heap = cdp.eval('performance.memory ? performance.memory.usedJSHeapSize : 0') or 0
        result['js_heap_mb'] = round(heap / 1e6, 1)
        result.update(network_summary(cdp.events))
        cdp.ws.close()
        return result
    finally:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            proc.terminate()
        shutil.rmtree(udd, ignore_errors=True)


def median_of(results, path):
    vals = []
    for r in results:
        v = r
        for key in path:
            v = v.get(key) if isinstance(v, dict) else None
        if isinstance(v, (int, float)):
            vals.append(v)
    return round(statistics.median(vals), 2) if vals else None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('url')
    ap.add_argument('--profile', choices=sorted(PROFILES), default='desktop')
    ap.add_argument('--cpu', type=float, help='CPU throttling rate (overrides the profile)')
    ap.add_argument('--runs', type=int, default=1, help='fresh-browser runs; medians reported when > 1')
    ap.add_argument('--settle', type=float, default=15, help='seconds to wait after first frame')
    ap.add_argument('--idle', type=float, default=5, help='idle measurement window, seconds')
    ap.add_argument('--scroll', choices=['auto', 'wheel', 'touch', 'none'], default='auto')
    ap.add_argument('--reduced-motion', action='store_true', help='emulate prefers-reduced-motion: reduce')
    ap.add_argument('--timeout', type=float, default=120, help='max seconds to wait for first frame')
    ap.add_argument('--port', type=int, default=9555)
    ap.add_argument('--chrome')
    ap.add_argument('--label', default='')
    ap.add_argument('--out')
    args = ap.parse_args()

    prof = dict(PROFILES[args.profile])
    if args.cpu:
        prof['cpu'] = args.cpu
    chrome_bin = find_chrome(args.chrome)

    runs = []
    for i in range(max(1, args.runs)):
        runs.append(run_once(args, prof, chrome_bin))
        print(f'run {i + 1}/{args.runs}: ttff={runs[-1]["ttff_ms"]} ms '
              f'idle={runs[-1]["idle"]["main_ms_per_frame"]} ms/frame', file=sys.stderr)

    out = {'label': args.label, 'url': args.url, 'profile': args.profile, 'cpu': prof['cpu'],
           'reduced_motion': args.reduced_motion, 'runs': runs}
    if len(runs) > 1:
        out['median'] = {
            'ttff_ms': median_of(runs, ['ttff_ms']),
            'idle_ms_per_frame': median_of(runs, ['idle', 'main_ms_per_frame']),
            'idle_busy_pct': median_of(runs, ['idle', 'main_busy_pct']),
            'scroll_ms_per_frame': median_of(runs, ['scroll', 'main_ms_per_frame']),
            'scroll_loaf_blocking_ms': median_of(runs, ['scroll', 'loaf_blocking_ms']),
            'transfer_kb': median_of(runs, ['transfer_kb']),
        }
    text = json.dumps(out, indent=1, ensure_ascii=False)
    print(text)
    if args.out:
        with open(args.out, 'w', encoding='utf-8') as fh:
            fh.write(text)


if __name__ == '__main__':
    main()
