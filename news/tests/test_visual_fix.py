"""Visual object migration tests. No order/trading simulation in these tests."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from test_integration import builder

ROOT=Path(__file__).resolve().parents[2]

class VisualFix(unittest.TestCase):
    def test_only_visual_namespace_and_version_differ_from_367(self):
        old=(ROOT/'Sniper_Manager_v3_6_7_NEWS_TESTER.mq5').read_text()
        new=builder.OUTPUT.read_text()
        reverted=builder.visual_fix.revert(new,old)
        reverted=reverted.replace('#property version "3.68"','#property version "3.67"')
        self.assertEqual(reverted.split('\n',1)[1],old.split('\n',1)[1])
    @unittest.skipUnless(shutil.which('g++'),'visual harness unrun: C++ compiler unavailable')
    def test_removes_old_sniper_layers_and_preserves_foreign_objects(self):
        fragment=(ROOT/'news/visual_namespace.mqpart').read_text()
        fragment=fragment.replace('string exact[]={','vector<string> exact={').replace('string groups[]={','vector<string> groups={')
        shim=r'''
#include <vector>
#include <string>
#include <cassert>
using namespace std;using ushort=unsigned short;
string G_VisualPrefix;
vector<string> objects,other_chart={"S36_00000001_DB_Txt_0"};int released=0;
int StringLen(string s){return s.size();}
int StringFind(string s,string t){auto p=s.find(t);return p==string::npos?-1:(int)p;}
string StringSubstr(string s,int p,int n=-1){return s.substr(p,n<0?string::npos:n);}
ushort StringGetCharacter(string s,int p){return s.at(p);}
int ArraySize(vector<string>&v){return v.size();}
void ReleasePanelCanvases(){released++;}
int ObjectsTotal(int chart,int,int){assert(chart==0);return objects.size();}
string ObjectName(int chart,int i,int,int){assert(chart==0);return objects.at(i);}
bool ObjectDelete(int chart,string s){assert(chart==0);for(int i=0;i<(int)objects.size();i++)if(objects[i]==s){objects.erase(objects.begin()+i);return true;}return false;}
void ChartRedraw(int chart){assert(chart==0);}
'''
        checks=r'''
int main(){
 objects={"Manual trendline","OtherTool_HUD","S36_foreign_DB_Txt_0","S36_AB12CD34_MyNote",
          "S36_00000001_DB_Txt_0","S36_AB12CD34_InfoOneRow_p1","S36_FFFFFFFF_NEWS_STATUS",
          "S36_12345678_H4_Confirm_050","S36_abcdef12_PriceCaption_gold",
          "S36_12345678_Txt_BaseZone_1","SN368V_DB_Txt_0","SN368V_NEWS_STATUS"};
 InitVisualNamespace();assert(G_VisualPrefix=="SN368V_");assert(objects.size()==4);
 assert(other_chart.size()==1);assert(released==1);
 objects.push_back(G_VisualPrefix+"DB_Txt_0");
 objects.push_back(G_VisualPrefix+"InfoOneRow");
 objects.push_back(G_VisualPrefix+"NEWS_STATUS");
 InitVisualNamespace();assert(objects.size()==4);assert(released==2);
 assert(!IsSniperVisualObject("S36_1234567X_DB_Txt_0"));
 assert(!IsSniperVisualObject("DB_Txt_0"));
 assert(!IsSniperVisualObject("S36_AB12CD34_UserDrawing"));
}
'''
        with tempfile.TemporaryDirectory() as directory:
            source=Path(directory)/'visual.cpp';exe=Path(directory)/'visual'
            source.write_text(shim+fragment+checks)
            result=subprocess.run(['g++','-std=c++17',str(source),'-o',str(exe)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            result=subprocess.run([str(exe)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
