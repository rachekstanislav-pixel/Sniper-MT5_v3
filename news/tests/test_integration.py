"""Static integration checks, NOT a substitute for MetaEditor or MT5."""
import importlib.util
from pathlib import Path
import re
import unittest
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('builder',ROOT/'news/build_integrated.py')
builder=importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

class Integration(unittest.TestCase):
    def test_generated_file_and_unchanged_base_bodies(self):
        output=builder.OUTPUT.read_text()
        self.assertEqual(output,builder.build())
        # Remove only the explicitly enumerated integration additions and engine.
        engine=(ROOT/'news/mt5/SniperNews.mqh').read_text()
        render=(ROOT/'news/render_status.mqpart').read_text()
        settings=(ROOT/'news/mt5/SniperNewsTesterSettings.mqh').read_text()
        adapter=(ROOT/'news/mt5/SniperNewsTester.mqh').read_text()
        restored=output.split('\n',1)[1].replace(settings+'\n'+engine+'\n'+adapter+'\n'+render+'\n','',1)
        for addition in ['   if(!News_TesterValidate(EnableAutoTrade,DiagnosticMode,MagicNumber)) return INIT_PARAMETERS_INCORRECT;\n',
                         '   News_InitOptional();\n   if(News_TesterOrders && !News_ready) return INIT_FAILED;\n',
                         '   News_OnDeinit(reason);\n   ObjectDelete(0,G_VisualPrefix+"NEWS_STATUS");\n',
                         '   // DiagnosticMode preserves the original promise: no network requests.\n   if(!DiagnosticMode) News_OnTimer();\n   News_RenderStatus();\n',
                         '   News_OnTick();\n']:
            self.assertEqual(restored.count(addition),1)
            restored=restored.replace(addition,'',1)
        restored=restored.replace('request.expiration=(datetime)((long)TimeCurrent()+(long)BaseMaxWaitBars*PeriodSeconds(_Period));', 'request.expiration=TimeCurrent()+(long)BaseMaxWaitBars*PeriodSeconds(_Period);')
        restored=restored.replace('#property version "3.67"', '#property version "3.65"')
        self.assertEqual(restored,builder.BASE.read_text())
    def test_engine_cannot_trade_or_remove_main_ea(self):
        engine=(ROOT/'news/mt5/SniperNews.mqh').read_text()
        for forbidden in ['OrderSend','OrderSendAsync','CTrade','Trade.mqh','PositionClose','PositionModify','ExpertRemove','EventSetTimer','EventKillTimer','Comment(']:
            self.assertNotIn(forbidden,engine)
        self.assertNotIn('WebRequest',(ROOT/'news/render_status.mqpart').read_text())
    def test_namespace_isolated(self):
        engine=(ROOT/'news/mt5/SniperNews.mqh').read_text()
        names=re.findall(r'^(?:void|bool|int)\s+(\w+)\(',engine,re.M)
        self.assertTrue(names)
        self.assertTrue(all(name.startswith('News_') for name in names))
