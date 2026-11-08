"""Source-derived execution-gate harness and preset checks; NOT MetaEditor/MT5."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]

def extract(text, name):
    start=text.index('bool '+name+'(')
    brace=text.index('{',start); depth=1; end=brace+1
    while depth:
        if text[end]=='{': depth+=1
        if text[end]=='}': depth-=1
        end+=1
    return text[start:end]

class TesterOrders(unittest.TestCase):
    def test_preset_disables_other_modules_and_loads_synthetic_file(self):
        text=(ROOT/'news/presets/NEWS_ONLY_SYNTHETIC_3.67.set').read_text(encoding='utf-16')
        values=dict(line.split('=',1) for line in text.splitlines() if line and not line.startswith(';'))
        for key in ('EnableAutoTrade','DiagnosticMode','EnableSMC_Base','EnableSMC_EMA','EnableSMC_Comp','EnableSMC_OTE','EnableSMC_Sweep','EnableAICommands'):
            self.assertEqual(values[key],'false')
        self.assertEqual(values['News_TesterOrders'],'true')
        self.assertEqual(values['News_Replay'],'true')
        self.assertTrue((ROOT/'news/fixtures'/values['News_ReplayFile']).exists())
        self.assertTrue(values['News_JournalFile'].startswith('TESTER_'))
        source=(ROOT/'Sniper_Manager_v3_6_7_NEWS_TESTER.mq5').read_text()
        for key in values:
            self.assertRegex(source,r'input\s+\w+\s+'+re.escape(key)+r'\s*=')
    @unittest.skipUnless(shutil.which('g++'),'C++ source harness not run: compiler unavailable')
    def test_live_guard_and_isolation_execute_before_order_apis(self):
        adapter=(ROOT/'news/mt5/SniperNewsTester.mqh').read_text()
        shim=r'''
#include <string>
#include <cmath>
#include <cassert>
using namespace std;
using ulong=unsigned long;
const int MQL_TESTER=1,MQL_OPTIMIZATION=2,INIT_PARAMETERS_INCORRECT=3;
const int TRADE_RETCODE_DONE=10009,TRADE_RETCODE_DONE_PARTIAL=10010;
bool tester=false,opt=false,News_TesterOrders=false;
ulong News_TesterMagic=9367001;
double News_TesterLots=.01;int News_TesterDeviationPoints=20;
string _Symbol="GOLD";
int checks=0,sends=0;bool checkOK=true,sendOK=true;
bool MQLInfoInteger(int key){return key==MQL_TESTER?tester:opt;}
bool MathIsValidNumber(double v){return isfinite(v);}
template<typename...T> void Print(T...){ }
struct MqlTradeRequest {ulong magic=9367001;string symbol="GOLD";};
struct MqlTradeResult {int retcode=10009;string comment="";};
struct MqlTradeCheckResult {int retcode=0;string comment="";};
bool News_TesterFill(MqlTradeRequest&){return true;}
bool OrderCheck(MqlTradeRequest&,MqlTradeCheckResult&){checks++;return checkOK;}
bool OrderSend(MqlTradeRequest&,MqlTradeResult&){sends++;return sendOK;}
'''
        checks=r'''
int main(){
 MqlTradeRequest q;MqlTradeResult r;
 // Live: neither enabling the input nor a forged request can reach order APIs.
 News_TesterOrders=true;assert(!News_TesterValidate(false,false,777));
 assert(!News_TesterSend(q,r));assert(checks==0&&sends==0);
 tester=true;assert(!News_TesterValidate(true,false,777));
 assert(!News_TesterValidate(false,true,777));
 assert(!News_TesterValidate(false,false,9367001));
 opt=true;assert(!News_TesterValidate(false,false,777));opt=false;
 assert(News_TesterValidate(false,false,777));
 News_TesterOrders=false;assert(!News_TesterSend(q,r));assert(sends==0);
 News_TesterOrders=true;q.magic=777;assert(!News_TesterSend(q,r));assert(sends==0);
 q.magic=9367001;q.symbol="EURUSD";assert(!News_TesterSend(q,r));assert(sends==0);
 q.symbol="GOLD";checkOK=false;assert(!News_TesterSend(q,r));assert(sends==0);
 checkOK=true;assert(News_TesterSend(q,r));assert(sends==1);
 tester=false;assert(!News_TesterSend(q,r));assert(sends==1);
}
'''
        with tempfile.TemporaryDirectory() as directory:
            source=Path(directory)/'gates.cpp'; exe=Path(directory)/'gates'
            source.write_text(shim+extract(adapter,'News_TesterValidate')+extract(adapter,'News_TesterSend')+checks)
            compile_result=subprocess.run(['g++','-std=c++17',str(source),'-o',str(exe)],capture_output=True,text=True)
            self.assertEqual(compile_result.returncode,0,compile_result.stderr)
            run=subprocess.run([str(exe)],capture_output=True,text=True)
            self.assertEqual(run.returncode,0,run.stderr)
