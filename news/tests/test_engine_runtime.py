"""Run actual news function bodies with a small C++ compatibility shim.
This is NOT MetaEditor compilation, a broker terminal, or a replacement for MT5 replay.
Quotes and clock are explicitly synthetic. Only listed function bodies are exercised.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ENGINE=Path(__file__).parents[1]/'mt5/SniperNews.mqh'

def body(name):
    text=ENGINE.read_text()
    start=text.index(('bool ' if name in ('News_Digits','News_ValidID') else 'void ')+name+'(')
    opening=text.index('{',start);depth=1;end=opening+1
    while depth:
        if text[end]=='{': depth+=1
        if text[end]=='}': depth-=1
        end+=1
    return text[start:end].replace('string f[];', 'vector<string> f;')

class Runtime(unittest.TestCase):
    @unittest.skipUnless(shutil.which('g++'),'C++ compiler unavailable: source-body harness unrun')
    def test_pause_recovery_quotes_stops_targets_dedupe(self):
        shim=r'''
#include <string>
#include <vector>
#include <cassert>
#include <cmath>
using namespace std;
using datetime=long; using ushort=unsigned short;
int StringLen(string s){return s.size();}
ushort StringGetCharacter(string s,int n){return s.at(n);}
long StringToInteger(string s){return stol(s);}
int StringSplit(string s,char delim,vector<string>& out){size_t p=0,q;while((q=s.find(delim,p))!=string::npos){out.push_back(s.substr(p,q-p));p=q+1;}out.push_back(s.substr(p));return out.size();}
string News_pending="",News_status="";vector<string> seen;vector<string> actions;
datetime News_available=0,News_expires=0,News_baseline_time=0,News_opened=0,News_last_valid=0,clock_now=0;
int News_direction=0,News_ConfirmationSeconds=60,News_HoldSeconds=60,News_MaxSpreadPoints=100;
double News_baseline=0,News_entry=0,News_sl=0,News_tp=0,_Point=.01,News_ConfirmationPoints=100,News_StopPoints=500,News_TargetPoints=1000;
bool News_active=false,News_ready=true,News_live_confirmed=false,News_Replay=false,News_Enabled=true;
struct MqlTick {double bid=100,ask=100.02;long time=0;} quote;
string _Symbol="GOLD"; const int MQL_TESTER=1; int News_ServerUTCOffsetSeconds=0;
bool MQLInfoInteger(int){return false;}
long TimeGMT(){return clock_now;}
bool SymbolInfoTick(string,MqlTick& t){t=quote;return true;}
bool News_Seen(string id){for(auto s:seen)if(s==id)return true;return false;}
void News_Remember(string id){seen.push_back(id);}
void News_Log(string,string action,long,double,double,string){actions.push_back(action);}
bool News_TesterOrders=false;
void News_TesterManage(long){}
bool News_TesterOpen(long,MqlTick&){return false;}
void News_Receive(long){}
void tick(long t,double bid){clock_now=t;quote.bid=bid;quote.ask=bid+.02;quote.time=t;}
'''
        functions='\n'.join(body(n) for n in ('News_Digits','News_ValidID','News_Pause','News_Accept','News_OnTick'))
        checks=r'''
int main(){
 string id(64,'a'), line=id+"\t1000\t1900\t1";
 tick(999,100);News_Accept(line,999);assert(News_pending.empty());
 tick(1000,100);News_Accept(line,1000);News_OnTick();assert(actions.size()==1&&actions[0]=="OBSERVE");
 tick(1030,100.5);News_Pause("WAIT");assert(News_pending==id&&!News_live_confirmed);
 tick(1060,102);News_OnTick();assert(!News_active&&actions.size()==1);
 News_Accept(line,1060);News_OnTick();assert(abs(News_baseline-102.01)<1e-8);
 tick(1119,104);News_Accept(line,1119);News_OnTick();assert(!News_active);
 tick(1120,104);News_Accept(line,1120);News_OnTick();assert(News_active&&actions[1]=="OPEN");
 News_Pause("outage");tick(1121,98);News_OnTick();assert(!News_active&&actions[2]=="CLOSE");
 News_Accept(line,1121);assert(News_pending.empty()&&actions.size()==3);
 string id2(64,'b');string sell=id2+"\t1200\t1900\t-1";
 tick(1200,100);News_Accept(sell,1200);assert(News_sl==0&&News_tp==0);News_OnTick();
 tick(1260,98);News_Accept(sell,1260);News_OnTick();assert(News_active&&News_direction==-1);
 tick(1261,87);News_OnTick();assert(!News_active);
 string id3(64,'c');tick(1300,100);News_Accept(id3+"\t1300\t1310\t1",1300);News_OnTick();
 tick(1311,102);News_OnTick();assert(News_pending.empty()&&!News_active&&actions.back()=="WAIT");
}
'''
        with tempfile.TemporaryDirectory() as directory:
            source=Path(directory)/'engine.cpp';exe=Path(directory)/'engine'
            source.write_text(shim+functions+checks)
            subprocess.run(['g++','-std=c++17',str(source),'-o',str(exe)],check=True,capture_output=True)
            run=subprocess.run([str(exe)],capture_output=True,text=True)
            self.assertEqual(run.returncode,0,run.stderr)
