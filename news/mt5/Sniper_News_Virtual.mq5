#property strict
#property version "0.10"
#property description "Separate news research EA. Virtual positions only."
input bool Replay=false;
input string ServiceURL="http://127.0.0.1:8765/signal.tsv";
input string ReplayFile="sniper_news.tsv";
input string JournalFile="sniper_news_virtual.tsv";
input int ServerUTCOffsetSeconds=0; // REQUIRED: historical broker offset incl. DST; use a constant-offset test interval
input int ConfirmationSeconds=60;
input double ConfirmationPoints=100;
input double StopPoints=500;
input double TargetPoints=1000;
input int HoldSeconds=1800;
input int MaxSpreadPoints=100;

string ids[], pending="", next="";
datetime available=0,expires=0,baseline_time=0,opened=0;
int direction=0,replay_handle=INVALID_HANDLE;
double baseline=0,entry=0,sl=0,tp=0;
bool active=false;

bool Seen(string id) { for(int i=0;i<ArraySize(ids);i++) if(ids[i]==id) return true; return false; }
void Remember(string id) { int n=ArraySize(ids); ArrayResize(ids,n+1); ids[n]=id; }
void Log(string id,string action,datetime utc,double price,double result,string reason) {
 int h=FileOpen(JournalFile,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
 if(h==INVALID_HANDLE) { Print("Journal unavailable; stopping to prevent unrecorded entries"); ExpertRemove(); return; }
 FileSeek(h,0,SEEK_END);
 FileWriteString(h,id+"\t"+action+"\t"+IntegerToString((long)utc)+"\t"+DoubleToString(price,_Digits)+"\t"+DoubleToString(sl,_Digits)+"\t"+DoubleToString(tp,_Digits)+"\t"+DoubleToString(result,2)+"\t"+reason+"\r\n");
 FileFlush(h); FileClose(h);
}
void Accept(string line,datetime now) {
 string f[]; if(StringSplit(line,'\t',f)!=4) return;
 string id=f[0]; long a=StringToInteger(f[1]),e=StringToInteger(f[2]); int d=(int)StringToInteger(f[3]);
 if(StringLen(id)!=64 || a<=0 || e<a || (d!=1 && d!=-1) || now<a || now>e || Seen(id)) return;
 // Never queue an old event behind an active position.
 Remember(id);
 if(active || pending!="") { Log(id,"WAIT",now,0,0,"busy; publication consumed"); return; }
 pending=id; available=(datetime)a; expires=(datetime)e; direction=d; baseline=0;
 Log(id,"OBSERVE",now,0,0,"rate hypothesis; awaiting post-availability price");
}
void Receive(datetime now) {
 if(Replay || MQLInfoInteger(MQL_TESTER)) {
  while(replay_handle!=INVALID_HANDLE) {
   if(next=="") { if(FileIsEnding(replay_handle)) break; next=FileReadString(replay_handle); }
   string f[];
   if(StringSplit(next,'\t',f)!=4) { next=""; continue; }
   if(StringToInteger(f[1])>now) break;
   Accept(next,now); next="";
  }
 } else {
  char request[],response[]; string headers;
  int code=WebRequest("GET",ServiceURL,"",3000,request,response,headers);
  if(code==200) {
   string line=CharArrayToString(response,0,-1,CP_UTF8); StringTrimRight(line); Accept(line,now);
  } else { pending=""; Print("WAIT: service unavailable ",code); }
 }
}
int OnInit() {
 if(_Period!=PERIOD_M5 || ConfirmationSeconds<1 || ConfirmationPoints<=0 || StopPoints<=0 || TargetPoints<=0 || HoldSeconds<1 || MaxSpreadPoints<1) return INIT_PARAMETERS_INCORRECT;
 Print("Virtual research only. Confirm symbol is broker GOLD/XAUUSD. No orders. UTC offset=",ServerUTCOffsetSeconds);
 // Recover consumed IDs; unresolved virtual trades are not reconstructed across restarts.
 int h=FileOpen(JournalFile,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
 if(h!=INVALID_HANDLE) {
  while(!FileIsEnding(h)) { string line=FileReadString(h), f[]; if(StringSplit(line,'\t',f)>1 && !Seen(f[0])) Remember(f[0]); }
  FileClose(h);
 }
 if(Replay || MQLInfoInteger(MQL_TESTER)) {
  replay_handle=FileOpen(ReplayFile,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
  if(replay_handle==INVALID_HANDLE) { Print("Replay file missing"); return INIT_FAILED; }
 }
 EventSetTimer(5); return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {
 EventKillTimer(); if(replay_handle!=INVALID_HANDLE) FileClose(replay_handle);
 if(active) Print("UNRESOLVED virtual position on shutdown: ",pending);
}
void OnTimer() { if(!MQLInfoInteger(MQL_TESTER)) Receive(TimeGMT()); }
void OnTick() {
 MqlTick tick; if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0 || tick.ask<tick.bid) return;
 datetime now=(Replay || MQLInfoInteger(MQL_TESTER)) ? tick.time-ServerUTCOffsetSeconds : TimeGMT();
 if(Replay || MQLInfoInteger(MQL_TESTER)) Receive(now);
 if(pending=="") return;
 if(active) {
  double exit_price=direction==1 ? tick.bid : tick.ask;
  bool stop=direction==1 ? exit_price<=sl : exit_price>=sl;
  bool target=direction==1 ? exit_price>=tp : exit_price<=tp;
  if(stop || target || now-opened>=HoldSeconds) {
   double pnl=direction*(exit_price-entry)/_Point;
   Log(pending,"CLOSE",now,exit_price,pnl,stop?"SL at observed quote":target?"target at observed quote":"time exit at observed quote");
   active=false; pending="";
  }
  return;
 }
 if(now>expires) { Log(pending,"WAIT",now,0,0,"expired without confirmation"); pending=""; return; }
 if(now<available) return;
 double mid=(tick.bid+tick.ask)/2;
 if(baseline==0) { baseline=mid; baseline_time=now; return; }
 if(now-baseline_time<ConfirmationSeconds || direction*(mid-baseline)<ConfirmationPoints*_Point || (tick.ask-tick.bid)/_Point>MaxSpreadPoints) return;
 entry=direction==1 ? tick.ask : tick.bid;
 sl=entry-direction*StopPoints*_Point; tp=entry+direction*TargetPoints*_Point;
 opened=now; active=true;
 Log(pending,"OPEN",now,entry,0,"spread included; zero latency/slippage/fees; no real order");
}
