"""Synthetic HTTP/XML fixtures; no claims about live source availability."""
import unittest
import urllib.error
from unittest.mock import patch
from test_service import s

class Diagnostics(unittest.TestCase):
    def test_http_codes(self):
        for code, category in [(403,'access_denied'),(404,'not_found'),(429,'rate_limited'),(500,'http_error')]:
            exc=urllib.error.HTTPError('https://www.bls.gov/feed/cpi.rss',code,'test',{},None)
            detail=s.error_detail('BLS',exc.url,exc)
            self.assertEqual(detail['http_status'],code)
            self.assertEqual(detail['category'],category)
            self.assertIn('url',detail)
    def test_proxy_error_is_distinct_and_redacted(self):
        e=urllib.error.URLError('Tunnel connection failed: 403 Forbidden secret-value')
        detail=s.error_detail('BLS','https://www.bls.gov/feed/cpi.rss',e)
        self.assertEqual(detail['proxy_http_status'],403)
        self.assertNotIn('http_status',detail)
        self.assertNotIn('secret-value',str(detail))
    def test_empty_and_html_are_errors(self):
        for raw in [b'<html><body>denied</body></html>', b'<rss><channel/></rss>']:
            with patch.object(s,'FEEDS',{'BLS':['https://www.bls.gov/feed/cpi.rss']}),patch.object(s,'fetch',return_value=raw):
                statuses=[]
                errors=s.poll(s.connect(':memory:'),statuses)
                self.assertEqual(len(errors),1)
                self.assertEqual(statuses[0]['state'],'error')
    def test_bea_release_host(self):
        raw=b'<rss><channel><item><title>Gross Domestic Product</title><link>https://www.bea.gov/news/2026/example</link><pubDate>Wed, 01 Oct 2025 18:00:00 GMT</pubDate></item></channel></rss>'
        events=s.parse_feed(raw,'BEA',2000000000)
        self.assertEqual(events[0]['event_type'],'GDP')
        self.assertEqual(s.decision(events[0],2000000000)[0],'WAIT')
