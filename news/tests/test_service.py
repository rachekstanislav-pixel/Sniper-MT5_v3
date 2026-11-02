import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('service', Path(__file__).parents[1]/'service.py')
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)

class Tests(unittest.TestCase):
    def event(self):
        return dict(id='a'*64, source='FED', event_type='RATE', published_at=1000,
                    received_at=1010, available_at=1010, numbers={'action':'lower'}, synthetic=False)
    def test_time_and_direction(self):
        e=self.event()
        self.assertEqual(s.decision(e,1009)[0],'WAIT')
        self.assertEqual(s.decision(e,1010)[0],'BUY')
        self.assertEqual(s.decision(e,1901)[0],'WAIT')
        e['numbers']['action']='raise'
        self.assertEqual(s.decision(e,1010)[0],'SELL')
    def test_wait(self):
        for change in [dict(numbers={}),dict(numbers={'action':'maintain'}),dict(source='BLS'),dict(synthetic=True)]:
            e=self.event();e.update(change)
            self.assertEqual(s.decision(e,1010)[0],'WAIT')
    def test_duplicates_preserve_availability(self):
        db=s.connect(':memory:');e=self.event()
        self.assertEqual(s.store(db,e),1)
        e['available_at']=1500
        self.assertEqual(s.store(db,e),0)
        self.assertEqual(s.rows(db)[0]['available_at'],1010)
    def test_rate_parser(self):
        self.assertEqual(s.rate_data('The Committee decided to lower the target range for the federal funds rate by 1/4 percentage point to 4.25 to 4.5 percent')['action'],'lower')
        self.assertEqual(s.rate_data('previous rate 5 percent; consensus lower'),{})
        self.assertEqual(s.rate_data('decided to raise the target range for the federal funds rate to 5 to 4 percent'),{})
    def test_feed(self):
        raw=b'<rss><channel><item><title>FOMC statement</title><link>https://www.federalreserve.gov/newsevents/pressreleases/test.htm</link><pubDate>Wed, 01 Oct 2025 18:00:00 GMT</pubDate></item></channel></rss>'
        e=s.parse_feed(raw,'FED',2000000000)[0]
        self.assertEqual(e['available_at'],2000000000)
        self.assertEqual(e['numbers'],{})
        self.assertEqual(e['event_type'],'RATE')
        self.assertEqual(s.parse_feed(raw.replace(b'www.federalreserve.gov',b'evil.example'),'FED',2000000000),[])
        with self.assertRaises(Exception): s.parse_feed(b'broken','FED',1)
    def test_no_trade_api(self):
        text=(Path(__file__).parents[1]/'mt5/SniperNews.mqh').read_text()
        for forbidden in ['OrderSend','OrderSendAsync','CTrade','Trade.mqh','PositionClose','PositionModify']:
            self.assertNotIn(forbidden,text)
    def test_poll_record_and_export_contract(self):
        from unittest.mock import patch
        rss=b'<rss><channel><item><title>FOMC statement</title><link>https://www.federalreserve.gov/newsevents/pressreleases/test.htm</link><pubDate>Wed, 01 Oct 2025 18:00:00 GMT</pubDate></item></channel></rss>'
        page=b'decided to lower the target range for the federal funds rate to 4.25 to 4.5 percent'
        db=s.connect(':memory:')
        with patch.object(s, 'FEEDS', {'FED':['https://www.federalreserve.gov/feed']}), patch.object(s, 'fetch', side_effect=[rss,page,rss]), patch.object(s.time, 'time', return_value=1759341610):
            self.assertEqual(s.poll(db),[])
            self.assertEqual(s.poll(db),[])
        events=s.rows(db)
        self.assertEqual(len(events),1)
        self.assertEqual(s.decision(events[0],1759341610)[0],'BUY')
        with patch.object(s, 'fetch', side_effect=OSError('offline')):
            self.assertTrue(s.poll(db))

    def test_replay_wire(self):
        e=self.event()
        self.assertEqual(s.wire(e,1010),'a'*64+'\t1010\t1900\t1\n')
        self.assertTrue(s.wire(e,1901).endswith('\t0\n'))

if __name__=='__main__': unittest.main()
