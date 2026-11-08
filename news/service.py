"""Standard-library, fail-closed official-news recorder. No broker integration."""
import argparse
import datetime as dt
import hashlib
import html
from html.parser import HTMLParser
import json
import re
import sqlite3
import time
import threading
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

FEEDS = {
    'FED': ['https://www.federalreserve.gov/feeds/press_monetary.xml'],
    'BLS': ['https://www.bls.gov/feed/cpi.rss', 'https://www.bls.gov/feed/empsit.rss'],
    'BEA': ['https://apps.bea.gov/rss/rss.xml'],
}
HOSTS = {'FED': {'www.federalreserve.gov'}, 'BLS': {'www.bls.gov'},
         'BEA': {'www.bea.gov', 'apps.bea.gov'}}
SERVICE_VERSION = '0.5.0'
PARSER_VERSION = 2
TTL = 900


def event_type(title):
    s = title.lower()
    for needles, kind in [(['fomc statement'], 'RATE'), (['consumer price index'], 'CPI'),
                           (['employment situation'], 'NFP_UNEMPLOYMENT'),
                           (['personal income and outlays'], 'PCE'), (['gross domestic product'], 'GDP')]:
        if any(n in s for n in needles):
            return kind
    return 'OTHER'


class ReleaseText(HTMLParser):
    """Retain word boundaries; discard executable/style text, not TLS checks."""
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.hidden = 0

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'):
            self.hidden += 1
        if tag in ('p', 'div', 'br', 'li'):
            self.parts.append(' ')

    def handle_endtag(self, tag):
        if tag in ('script', 'style'):
            self.hidden = max(0, self.hidden - 1)
        if tag in ('p', 'div', 'li'):
            self.parts.append(' ')

    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(data)


def rate_data(text):
    parser = ReleaseText()
    parser.feed(text)
    text = html.unescape(''.join(parser.parts))
    # Official releases may use typographic hyphens and Unicode fraction glyphs.
    text = text.translate(str.maketrans({'–': '-', '−': '-', '‑': '-', '⁄': '/'}))
    for glyph, fraction in {'¼': '1/4', '½': '1/2', '¾': '3/4'}.items():
        text = re.sub(r'(\d)\s*' + glyph, lambda m: m[1] + '-' + fraction, text)
        text = text.replace(glyph, fraction)
    text = re.sub(r'\s+', ' ', text)
    number = r'(?:\d+-\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)'
    pattern = (r'decided to (raise|lower|maintain) the target range for the federal funds rate '
               r'(?:by [^.;]{1,100}? to|to|at) (' + number + r') to (' + number + r') percent')
    def value(token):
        whole, fraction = token.split('-', 1) if '-' in token else ('0', token)
        if '/' in fraction:
            numerator, denominator = map(float, fraction.split('/'))
            if denominator <= 0 or numerator >= denominator:
                raise ValueError('invalid proper fraction')
            return float(whole) + numerator / denominator
        return float(fraction)
    matches = []
    for m in re.finditer(pattern, text, re.I):
        try:
            lo, hi = value(m[2]), value(m[3])
        except (ValueError, ZeroDivisionError):
            return {}
        if not 0 <= lo <= hi <= 30 or hi - lo > 1:
            return {}
        matches.append({'action': m[1].lower(), 'target_low_pct': lo, 'target_high_pct': hi})
    # Contradictory statements must not produce a direction.
    return matches[0] if matches and all(m == matches[0] for m in matches) else {}


def parse_feed(data, source, received):
    root = ET.fromstring(data)
    atom = '{http://www.w3.org/2005/Atom}'
    is_atom = root.tag == atom + 'feed'
    if not is_atom and (root.tag != 'rss' or root.find('channel') is None):
        raise ValueError('expected RSS 2.0 or Atom feed')
    events = []
    items = root.findall(atom + 'entry') if is_atom else root.findall('./channel/item')
    for item in items:
        if is_atom:
            title = item.findtext(atom + 'title', '').strip()
            links = [link.get('href', '') for link in item.findall(atom + 'link')
                     if link.get('rel', 'alternate') == 'alternate']
            url = links[0].strip() if links else ''
            # Never substitute feed-level updated or entry updated for publication time.
            date = item.findtext(atom + 'published', '').strip()
        else:
            title, url, date = (item.findtext(k, '').strip() for k in ('title', 'link', 'pubDate'))
        from urllib.parse import urlparse
        p = urlparse(url)
        if p.scheme != 'https' or p.hostname not in HOSTS[source] or p.username or not title:
            continue
        try:
            stamp = dt.datetime.fromisoformat(date.replace('Z', '+00:00')) if is_atom else parsedate_to_datetime(date)
            if stamp.tzinfo is None:
                continue
            published = int(stamp.timestamp())
        except (ValueError, TypeError, OverflowError):
            continue
        # BLS entry headlines say "CPI ...", not necessarily "Consumer Price Index".
        kind = event_type(title)
        if source == 'BLS' and is_atom:
            feed_id = root.findtext(atom + 'id', '').lower()
            if feed_id == 'bls.gov:feed:cpi':
                kind = 'CPI'
            elif feed_id == 'bls.gov:feed:empsit':
                kind = 'NFP_UNEMPLOYMENT'
        identity = hashlib.sha256((source + '\n' + url).encode()).hexdigest()
        events.append(dict(id=identity, source=source, url=url, published_at=published,
                           received_at=received, available_at=max(published, received),
                           event_type=kind, title=title, numbers={}, synthetic=False))
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
    if action == 'maintain':
        return 'WAIT', 'rate unchanged: no directional hypothesis'
    return 'WAIT', e.get('parse_status', 'rate text not parsed')


def connect(path):
    db = sqlite3.connect(path)
    db.execute('CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, data TEXT NOT NULL)')
    db.execute('CREATE TABLE IF NOT EXISTS documents (url TEXT, sha256 TEXT, received_at INTEGER, body BLOB, PRIMARY KEY(url, sha256))')
    return db


def store(db, e):
    # First observation is immutable: polling cannot refresh an old publication's TTL.
    with db:
        return db.execute('INSERT OR IGNORE INTO events VALUES (?,?)', (e['id'], json.dumps(e, ensure_ascii=False))).rowcount


def archive(db, url, body, received):
    digest = hashlib.sha256(body).hexdigest()
    with db:
        db.execute('INSERT OR IGNORE INTO documents VALUES (?,?,?,?)', (url, digest, received, body))
    return digest


def enrich_rate(db, e):
    if e['source'] != 'FED' or e['event_type'] != 'RATE':
        return e
    if e.get('numbers'):
        return e  # Never rewrite an already interpreted decision from a revised page.
    now = int(time.time())
    if e.get('parser_version') == PARSER_VERSION:
        # Unknown wording is reparsed on a parser upgrade; transient HTTP errors retry.
        if e.get('parse_status') == 'unrecognized_rate_text':
            return e
        if now - e.get('last_analysis_attempt', 0) < 60:
            return e
    e['last_analysis_attempt'] = now
    e['parser_version'] = PARSER_VERSION
    try:
        raw = fetch(e['url'])
        received = int(time.time())
        e['document_sha256'] = archive(db, e['url'], raw, received)
        e['numbers'] = rate_data(raw.decode('utf-8-sig'))
        e['analysis_received_at'] = received
        # The interpretation cannot be visible before its supporting content arrived.
        # Keep the FIRST feed observation and publication timestamps unchanged.
        e['available_at'] = max(e['available_at'], received)
        e['parse_status'] = 'parsed' if e['numbers'] else 'unrecognized_rate_text'
        e.pop('parse_error', None)
    except Exception as exc:
        e['parse_status'] = 'release_fetch_or_parse_failed'
        e['parse_error'] = error_detail(e['source'], e['url'], exc)
    return e


def fetch(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'SniperNewsResearch/0.1 (personal noncommercial research)'})
    with urllib.request.urlopen(request, timeout=20) as r:
        return r.read(4_000_000)


def error_detail(source, url, exc):
    # Never expose headers, response bodies, proxy credentials or arbitrary exception text.
    result = {'source': source, 'url': url, 'error': type(exc).__name__}
    if isinstance(exc, urllib.error.HTTPError):
        result['http_status'] = exc.code
        result['category'] = {403: 'access_denied', 404: 'not_found', 410: 'gone',
                              429: 'rate_limited'}.get(exc.code, 'http_error')
        if exc.code == 403:
            result['hint'] = 'Source or gateway denied access; not evidence of a missing feed. No bypass attempted.'
        elif exc.code in (404, 410):
            result['hint'] = 'Feed URL is missing or retired; verify the official RSS listing.'
    elif isinstance(exc, urllib.error.URLError):
        reason = str(exc.reason)
        proxy = re.search(r'Tunnel connection failed: (\d{3})', reason)
        result['category'] = 'proxy_connect_error' if proxy else 'network_or_tls_error'
        if proxy:
            result['proxy_http_status'] = int(proxy[1])
    elif isinstance(exc, ET.ParseError):
        result['category'] = 'invalid_xml'
    elif isinstance(exc, ValueError):
        result['category'] = 'unsupported_or_empty_feed'
    else:
        result['category'] = 'processing_error'
    return result


def poll(db, statuses=None):
    errors = []
    for source, urls in FEEDS.items():
        for url in urls:
            try:
                raw = fetch(url)
                received = int(time.time())
                archive(db, url, raw, received)
                parsed = parse_feed(raw, source, received)
                if not parsed:
                    raise ValueError('no usable publication records')
                if statuses is not None:
                    statuses.append({'source': source, 'url': url, 'state': 'ok',
                                     'checked_at': received, 'parsed_events': len(parsed)})
                for incoming in parsed:
                    existing = db.execute('SELECT data FROM events WHERE id=?', (incoming['id'],)).fetchone()
                    e = json.loads(existing[0]) if existing else incoming
                    e = enrich_rate(db, e)
                    if existing:
                        with db:
                            db.execute('UPDATE events SET data=? WHERE id=?', (json.dumps(e, ensure_ascii=False), e['id']))
                    else:
                        store(db, e)

            except Exception as exc:
                detail = error_detail(source, url, exc)
                errors.append(detail)
                if statuses is not None:
                    statuses.append(dict(detail, state='error', checked_at=int(time.time())))
    return errors


def rows(db):
    return sorted((json.loads(r[0]) for r in db.execute('SELECT data FROM events')), key=lambda e: (e['available_at'], e['id']))


def wire(e, now):
    side, _ = decision(e, now)
    direction = {'BUY': 1, 'SELL': -1, 'WAIT': 0}[side]
    return f"{e['id']}\t{e['available_at']}\t{e['published_at'] + TTL}\t{direction}\n"


def evaluated(e, now, statuses, collector_ready):
    if not collector_ready:
        return 'WAIT', 'collector not ready, refreshing or stale'
    matching = [x for x in statuses if x.get('source') == e['source']]
    if not matching or any(x.get('state') != 'ok' or now - x.get('checked_at', 0) > 120
                           or x.get('checked_at', 0) > now for x in matching):
        return 'WAIT', 'publication source unavailable or stale'
    return decision(e, now)


def signal_payload(events, now, statuses, collector_ready):
    # Collection-only publications must not mask a valid FED rate candidate.
    eligible = [e for e in events if evaluated(e, now, statuses, collector_ready)[0] in ('BUY', 'SELL')]
    return wire(eligible[-1], now) if eligible else 'WAIT\t0\t0\t0\n'


def diagnose(events, now, statuses, ready):
    from collections import Counter
    reasons = Counter()
    for e in events:
        side, reason = evaluated(e, now, statuses, ready)
        reasons[reason] += 1
    rates = [e for e in events if e['source'] == 'FED' and e['event_type'] == 'RATE']
    latest = max(rates, key=lambda e: e['published_at']) if rates else None
    selected = signal_payload(events, now, statuses, ready).split('\t')[0]
    if not ready:
        terminal_state = 'COLLECTOR_PAUSED'
    elif selected != 'WAIT':
        terminal_state = 'RATE_CANDIDATE'
    elif latest is None:
        terminal_state = 'NO_RATE_PUBLICATION'
    else:
        reason = evaluated(latest, now, statuses, ready)[1]
        terminal_state = {
            'stale publication': 'STALE_RATE',
            'rate unchanged: no directional hypothesis': 'RATE_UNCHANGED',
            'publication source unavailable or stale': 'FED_UNAVAILABLE',
            'unrecognized_rate_text': 'RATE_TEXT_UNRECOGNIZED',
            'release_fetch_or_parse_failed': 'RATE_RELEASE_ERROR',
            'not yet available': 'NOT_YET_AVAILABLE',
        }.get(reason, 'NO_VALID_RATE_SIGNAL')
    return {
        'terminal_state': terminal_state,
        'scope': 'Only FED rate changes can give directions; BLS/BEA collection only',
        'collector_ready': ready,
        'signal': 'WAIT' if selected == 'WAIT' else next(
            (evaluated(e, now, statuses, ready)[0] for e in events if e['id'] == selected), 'WAIT'),
        'wait_reasons': dict(reasons),
        'latest_fed_rate': None if latest is None else {
            'id': latest['id'], 'url': latest['url'], 'published_at': latest['published_at'],
            'first_received_at': latest['received_at'], 'available_at': latest['available_at'],
            'age_seconds': now - latest['published_at'], 'expires_at': latest['published_at'] + TTL,
            'numbers': latest.get('numbers', {}), 'parse_status': latest.get('parse_status', 'legacy_record'),
            'parse_error': latest.get('parse_error'),
            'current_decision': evaluated(latest, now, statuses, ready),
        },
    }


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
        statuses = []
        errors = poll(db, statuses)
        print(json.dumps({'version': SERVICE_VERSION, 'sources': statuses, 'errors': errors, 'events': len(rows(db)), 'diagnostics': diagnose(rows(db), int(time.time()), statuses, True)}, indent=2))
        raise SystemExit(bool(errors))
    state = {'last_poll': 0, 'errors': ['not polled'], 'sources': [], 'refreshing': True}
    stop = threading.Event()

    def collect():
        worker_db = connect(args.db)
        try:
            while not stop.is_set():
                state['refreshing'] = True
                state['errors'] = ['refresh in progress']
                try:
                    statuses = []
                    state['errors'] = poll(worker_db, statuses)
                    state['sources'] = statuses
                    print(json.dumps({'version': SERVICE_VERSION, 'sources': statuses}, ensure_ascii=False), flush=True)
                except Exception as exc:
                    state['errors'] = [{'error': type(exc).__name__}]
                state['last_poll'] = int(time.time())
                state['refreshing'] = False
                stop.wait(60)
        finally:
            worker_db.close()

    threading.Thread(target=collect, daemon=True).start()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            now = int(time.time())
            errors = state['errors']
            if not state['last_poll'] or now - state['last_poll'] > 120:
                errors = ['collector stale']
            statuses = state['sources']
            ready = bool(state['last_poll']) and now - state['last_poll'] <= 120 and not state['refreshing']
            # Unexpected collector failures block every source; ordinary per-source errors do not.
            ready = ready and all(isinstance(x, dict) and 'source' in x for x in errors)
            events = rows(db)
            if self.path == '/status':
                body = json.dumps({'version': SERVICE_VERSION, 'sources': statuses, 'errors': errors,
                                   'diagnostics': diagnose(events, now, statuses, ready)}, ensure_ascii=False, indent=2).encode()
                content_type = 'application/json; charset=utf-8'
            elif self.path == '/events':
                for e in events:
                    side, reason = evaluated(e, now, statuses, ready)
                    e['signal'] = side
                    e['reason'] = reason
                    e['expires_at'] = e['published_at'] + TTL
                body = json.dumps({'version': SERVICE_VERSION, 'sources': state['sources'], 'diagnostics': diagnose(events, now, statuses, ready), 'events': events, 'errors': errors}, ensure_ascii=False, indent=2).encode()
                content_type = 'application/json; charset=utf-8'
            elif self.path == '/signal.tsv':
                body = signal_payload(events, now, statuses, ready).encode()
                content_type = 'text/plain'
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            if self.path == '/signal.tsv':
                self.send_header('X-Sniper-State', diagnose(events, now, statuses, ready)['terminal_state'])
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
    server = HTTPServer(('127.0.0.1', args.port), Handler)
    print(f'SniperNews {SERVICE_VERSION}: http://127.0.0.1:{args.port}/status', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("News service stopped.", flush=True)
    finally:
        stop.set()
        server.server_close()
        db.close()


if __name__ == '__main__':
    main()
