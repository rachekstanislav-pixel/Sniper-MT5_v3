"""Synthetic Atom examples matching the structure shown by the user."""
import unittest
from test_service import s

class Atom(unittest.TestCase):
    def feed(self, published='2026-10-14T07:50:31.2-04:00', feed_id='cpi'):
        return f'''<feed xmlns="http://www.w3.org/2005/Atom"><id>bls.gov:feed:{feed_id}</id>
        <entry><title>CPI for all items increases 0.6%</title><link href="https://www.bls.gov/news.release/archives/cpi_10142026.htm"/>
        <published>{published}</published><updated>2026-11-01T12:00:00Z</updated></entry></feed>'''.encode()
    def test_cpi_and_timezone(self):
        e=s.parse_feed(self.feed(),'BLS',2000000000)[0]
        self.assertEqual(e['event_type'],'CPI')
        self.assertEqual(e['published_at'],int(s.dt.datetime.fromisoformat('2026-10-14T11:50:31.2+00:00').timestamp()))
        self.assertEqual(e['available_at'],2000000000)
        self.assertEqual(s.decision(e,2000000000)[0],'WAIT')
    def test_employment_feed(self):
        e=s.parse_feed(self.feed(feed_id='empsit'),'BLS',2000000000)[0]
        self.assertEqual(e['event_type'],'NFP_UNEMPLOYMENT')
    def test_no_invented_publication_time(self):
        for value in ['', 'not-a-date', '2026-10-14T12:00:00']:
            self.assertEqual(s.parse_feed(self.feed(value),'BLS',2000000000),[])
    def test_untrusted_link(self):
        self.assertEqual(s.parse_feed(self.feed().replace(b'www.bls.gov',b'evil.example'),'BLS',2000000000),[])
    def test_dedupe_unchanged(self):
        db=s.connect(':memory:')
        e=s.parse_feed(self.feed(),'BLS',2000000000)[0]
        self.assertEqual(s.store(db,e),1)
        later=s.parse_feed(self.feed(),'BLS',2000000100)[0]
        self.assertEqual(s.store(db,later),0)
        self.assertEqual(s.rows(db)[0]['received_at'],2000000000)
