"""Standard-library, fail-closed official-news recorder. No broker integration."""
import argparse
import datetime as dt
import hashlib
import html
import json
import re
import sqlite3
import time
import urllib.request
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

FEEDS = {
    'FED': ['https://www.federalreserve.gov/feeds/press_monetary.xml'],
    'BLS': ['https://www.bls.gov/feed/cpi.rss', 'https://www.bls.gov/feed/empsit.rss'],
    'BEA': ['https://www.bea.gov/news/feed'],
}
HOSTS = {'FED': 'www.federalreserve.gov', 'BLS': 'www.bls.gov', 'BEA': 'www.bea.gov'}
TTL = 900


def event_type(title):
    s = title.lower()
    for needles, kind in [(['fomc statement'], 'RATE'), (['consumer price index'], 'CPI'),
                           (['employment situation'], 'NFP_UNEMPLOYMENT'),
                           (['personal income and outlays'], 'PCE'), (['gross domestic product'], 'GDP')]:
        if any(n in s for n in needles):
            return kind
    return 'OTHER'


def rate_data(text):
    # Only an explicit direction AND an explicit new target range. No inferred consensus.
    s = html.unescape(re.sub('<[^>]+>', ' ', text))
    s = re.sub(r'\s+', ' ', s)
    m = re.search(r'decided to (raise|lower|maintain) the target range for the federal funds rate (?:by .*? to|to|at) (\d+(?:\.\d+)?) to (\d+(?:\.\d+)?) percent', s, re.I)
    if not m:
        return {}
    lo, hi = float(m[2]), float(m[3])
    if not 0 <= lo <= hi <= 30:
        return {}
    return {'action': m[1].lower(), 'target_low_pct': lo, 'target_high_pct': hi}


def parse_feed(data, source, received):
    root = ET.fromstring(data)
    events = []
    for item in root.findall('.//item'):
        title, url, date = (item.findtext(k, '').strip() for k in ('title', 'link', 'pubDate'))
        from urllib.parse import urlparse
        p = urlparse(url)
        if p.scheme != 'https' or p.hostname != HOSTS[source] or p.username or not title:
            continue
        try:
            stamp = parsedate_to_datetime(date)
            if stamp.tzinfo is None:
                continue
            published = int(stamp.timestamp())
        except (ValueError, TypeError, OverflowError):
            continue
        identity = hashlib.sha256((source + '\n' + url).encode()).hexdigest()
        events.append(dict(id=identity, source=source, url=url, published_at=published,
                           received_at=received, available_at=max(published, received),
                           event_type=event_type(title), title=title, numbers={}, synthetic=False))
    return events


def decision(e, now):
    if e.get('synthetic'):
        return 'WAIT', 'synthetic publication: live direction disabled'
    if now < e['available_at']:
        return 'WAIT', 'not yet available'
    if now > e['published_at'] + TTL:
        return 'WAIT', 'stale publication'
    if e['source'] != 'FED' or e['event_type'] != 'RATE':
        return 'WAIT', 'collection only; no consensus assumption'
    action = e['numbers'].get('action')
    if action in ('lower', 'raise'):
        return ('BUY' if action == 'lower' else 'SELL'), 'rate-change hypothesis; price confirmation required'
    return 'WAIT', 'missing unambiguous rate change or unchanged rate'


def connect(path):
    db = sqlite3.connect(path)
    db.execute('CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, data TEXT NOT NULL)')
    return db


def store(db, e):
    # First observation is immutable: polling cannot refresh an old publication's TTL.
    with db:
        return db.execute('INSERT OR IGNORE INTO events VALUES (?,?)', (e['id'], json.dumps(e, ensure_ascii=False))).rowcount


def fetch(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'SniperNewsResearch/0.1 (personal noncommercial research)'})
    with urllib.request.urlopen(request, timeout=20) as r:
        return r.read(4_000_000)


def poll(db):
    errors = []
    for source, urls in FEEDS.items():
        for url in urls:
            try:
                raw = fetch(url)
                received = int(time.time())
                for e in parse_feed(raw, source, received):
                    if db.execute('SELECT 1 FROM events WHERE id=?', (e['id'],)).fetchone():
                        continue
                    if source == 'FED' and e['event_type'] == 'RATE':
                        try:
                            page = fetch(e['url']).decode('utf-8')
                            e['numbers'] = rate_data(page)
                            e['received_at'] = int(time.time())
                            e['available_at'] = max(e['published_at'], e['received_at'])
                        except Exception as exc:
                            e['parse_error'] = type(exc).__name__
                    store(db, e)
            except Exception as exc:
                errors.append({'source': source, 'error': type(exc).__name__})
    return errors


def rows(db):
    return sorted((json.loads(r[0]) for r in db.execute('SELECT data FROM events')), key=lambda e: (e['available_at'], e['id']))


def wire(e, now):
    side, _ = decision(e, now)
    direction = {'BUY': 1, 'SELL': -1, 'WAIT': 0}[side]
    return f"{e['id']}\t{e['available_at']}\t{e['published_at'] + TTL}\t{direction}\n"


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--db', default='news.sqlite3')
    p.add_argument('--port', type=int, default=8765)
    p.add_argument('--export', help='export recorded events to this prefix (.jsonl/.tsv)')
    p.add_argument('--once', action='store_true')
    args = p.parse_args()
    db = connect(args.db)
    if args.export:
        events = rows(db)
        Path(args.export + '.jsonl').write_text(''.join(json.dumps(e, ensure_ascii=False) + '\n' for e in events), encoding='utf-8')
        Path(args.export + '.tsv').write_text(''.join(wire(e, e['available_at']) for e in events), encoding='ascii')
        return
    if args.once:
        errors = poll(db)
        print(json.dumps({'errors': errors, 'events': len(rows(db)), 'signal': 'WAIT' if errors else 'see events'}))
        raise SystemExit(bool(errors))
    state = {'last_poll': 0, 'errors': ['not polled']}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            now = int(time.time())
            if now - state['last_poll'] >= 60:
                state['errors'] = poll(db)
                state['last_poll'] = int(time.time())
                now = int(time.time())
            events = rows(db)
            if self.path == '/events':
                for e in events:
                    side, reason = decision(e, now)
                    e['signal'] = 'WAIT' if state['errors'] else side
                    e['reason'] = 'source fetch failed' if state['errors'] else reason
                    e['expires_at'] = e['published_at'] + TTL
                body = json.dumps({'events': events, 'errors': state['errors']}, ensure_ascii=False).encode()
                content_type = 'application/json; charset=utf-8'
            elif self.path == '/signal.tsv':
                eligible = [e for e in events if e['available_at'] <= now <= e['published_at'] + TTL]
                body = (wire(eligible[-1], now) if eligible and not state['errors'] else 'WAIT\t0\t0\t0\n').encode()
                content_type = 'text/plain'
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
    HTTPServer(('127.0.0.1', args.port), Handler).serve_forever()


if __name__ == '__main__':
    main()
