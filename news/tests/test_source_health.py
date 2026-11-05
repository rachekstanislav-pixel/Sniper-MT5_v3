"""Synthetic publications: source isolation, not historical trading evidence."""
import unittest
from test_service import s

class Health(unittest.TestCase):
    def event(self, source='FED'):
        return dict(id='a'*64,source=source,event_type='RATE',published_at=1000,
                    received_at=1010,available_at=1010,numbers={'action':'lower'},synthetic=False)
    def statuses(self):
        return [dict(source='FED',state='ok',checked_at=1010),dict(source='BLS',state='error',checked_at=1010)]
    def test_bls_does_not_block_fed(self):
        self.assertEqual(s.evaluated(self.event(),1010,self.statuses(),True)[0],'BUY')
        self.assertEqual(s.evaluated(self.event('BLS'),1010,self.statuses(),True)[0],'WAIT')
    def test_fail_closed(self):
        for statuses,ready,now in [(self.statuses(),False,1010),([],True,1010),(self.statuses(),True,1200)]:
            self.assertEqual(s.evaluated(self.event(),now,statuses,ready)[0],'WAIT')
        self.assertEqual(s.evaluated(self.event(),1009,self.statuses(),True)[0],'WAIT')
    def test_collection_event_cannot_mask_rate(self):
        statuses=self.statuses()+[dict(source='BEA',state='ok',checked_at=1010)]
        other=self.event('BEA');other['event_type']='GDP'
        self.assertTrue(s.signal_payload([self.event(),other],1010,statuses,True).endswith('\t1\n'))
    def test_rate_source_failure_blocks(self):
        statuses=[dict(source='FED',state='error',checked_at=1010)]
        self.assertEqual(s.signal_payload([self.event()],1010,statuses,True),'WAIT\t0\t0\t0\n')

    def test_fed_fraction_range(self):
        text='The Committee decided to lower the target range for the federal funds rate by 1/4 percentage point to 3-3/4 to 4 percent.'
        self.assertEqual(s.rate_data(text),dict(action='lower',target_low_pct=3.75,target_high_pct=4.0))
        self.assertEqual(s.rate_data(text.replace('3-3/4','3-3/0')),{})
