"""Synthetic release fixtures; no claim that these texts were fetched from FED."""
import json
import unittest
from unittest.mock import patch
from test_service import s

class Repair(unittest.TestCase):
    def event(self):
        return dict(id='a'*64,source='FED',event_type='RATE',url='https://www.federalreserve.gov/test-release',
                    published_at=1000,received_at=1010,available_at=1010,numbers={},synthetic=False)
    def test_fraction_html_and_conflict(self):
        for token in ['4¼','4&frac14;','4-1/4','4‑1/4']:
            text=f'<p>The Committee decided to lower the target range for the federal funds rate by 1/4 percentage point to {token} to 4½ percent.</p>'
            self.assertEqual(s.rate_data(text),dict(action='lower',target_low_pct=4.25,target_high_pct=4.5))
        self.assertEqual(s.rate_data('decided to lower the target range for the federal funds rate to 4.25 to 4.5 percent; decided to raise the target range for the federal funds rate to 4.25 to 4.5 percent'),{})
        self.assertEqual(s.rate_data('<script>decided to lower the target range for the federal funds rate to 4 to 4.25 percent</script>'),{})
    def test_transient_release_failure_recovers_without_time_travel(self):
        db=s.connect(':memory:'); e=self.event()
        with patch.object(s,'fetch',side_effect=OSError('temporary')),patch.object(s.time,'time',return_value=1020):
            e=s.enrich_rate(db,e)
        self.assertEqual(e['parse_status'],'release_fetch_or_parse_failed')
        page=b'decided to lower the target range for the federal funds rate to 4 to 4.25 percent'
        with patch.object(s,'fetch',return_value=page),patch.object(s.time,'time',return_value=1081):
            e=s.enrich_rate(db,e)
        self.assertEqual(e['received_at'],1010)
        self.assertEqual(e['available_at'],1081)
        self.assertEqual(s.decision(e,1080)[0],'WAIT')
        self.assertEqual(s.decision(e,1081)[0],'BUY')
        self.assertEqual(db.execute('SELECT count(*) FROM documents').fetchone()[0],1)
    def test_poll_repairs_existing_empty_record(self):
        db=s.connect(':memory:')
        rss=b'<rss><channel><item><title>FOMC statement</title><link>https://www.federalreserve.gov/test-release</link><pubDate>Thu, 01 Jan 1970 00:16:40 GMT</pubDate></item></channel></rss>'
        e=s.parse_feed(rss,'FED',1010)[0];s.store(db,e)
        page=b'decided to lower the target range for the federal funds rate to 4 to 4.25 percent'
        with patch.object(s,'FEEDS',{'FED':['https://www.federalreserve.gov/feed']}),patch.object(s,'fetch',side_effect=[rss,page]),patch.object(s.time,'time',return_value=1100):
            self.assertEqual(s.poll(db),[])
        repaired=s.rows(db)[0]
        self.assertEqual(repaired['numbers']['action'],'lower')
        self.assertEqual(repaired['received_at'],1010)
        self.assertEqual(repaired['available_at'],1100)
    def test_stale_repair_never_revives_old_news(self):
        db=s.connect(':memory:');e=self.event()
        with patch.object(s,'fetch',return_value=b'decided to raise the target range for the federal funds rate to 4 to 4.25 percent'),patch.object(s.time,'time',return_value=3000):
            e=s.enrich_rate(db,e)
        self.assertEqual(s.decision(e,3000),('WAIT','stale publication'))
        status=[dict(source='FED',state='ok',checked_at=3000)]
        d=s.diagnose([e],3000,status,True)
        self.assertEqual(d['signal'],'WAIT')
        self.assertEqual(d['latest_fed_rate']['numbers']['action'],'raise')
        self.assertEqual(d['latest_fed_rate']['parse_status'],'parsed')
    def test_successful_interpretation_not_replaced(self):
        e=self.event();e['numbers']={'action':'lower','target_low_pct':4,'target_high_pct':4.25}
        with patch.object(s,'fetch') as fetch:
            self.assertEqual(s.enrich_rate(s.connect(':memory:'),e),e)
            fetch.assert_not_called()
