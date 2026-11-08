// Isolated virtual news engine. No real trading APIs.
input bool News_Enabled=true; // Virtual news only; does not gate BASE trading
input bool News_Replay=false;
input string News_ServiceURL="http://127.0.0.1:8765/signal.tsv";
input string News_ReplayFile="sniper_news.tsv";
input string News_JournalFile="sniper_news_virtual.tsv";
input int News_ServerUTCOffsetSeconds=0; // REQUIRED: historical broker offset incl. DST; use a constant-offset test interval
input int News_ConfirmationSeconds=60;
input double News_ConfirmationPoints=100;
input double News_StopPoints=500;
input double News_TargetPoints=1000;
input int News_HoldSeconds=1800;
input int News_MaxSpreadPoints=100;

string News_ids[], News_pending="", News_next="";
datetime News_available=0,News_expires=0,News_baseline_time=0,News_opened=0;
int News_direction=0,News_replay_handle=INVALID_HANDLE;
double News_baseline=0,News_entry=0,News_sl=0,News_tp=0;
bool News_active=false;
bool News_ready=false;
bool News_live_confirmed=false;
datetime News_last_valid=0;
string News_status="WAIT: initializing";
ulong News_last_poll=0;

bool News_Seen(string id) { for(int i=0;i<ArraySize(News_ids);i++) if(News_ids[i]==id) return true; return false; }
void News_Remember(string id) { int n=ArraySize(News_ids); ArrayResize(News_ids,n+1); News_ids[n]=id; }
void News_Log(string id,string action,datetime utc,double price,double result,string reason) {
 int h=FileOpen(News_JournalFile,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
 if(h==INVALID_HANDLE) { Print("Journal unavailable; stopping to prevent unrecorded entries"); News_ready=false; News_status="WAIT: journal unavailable"; return; }
 FileSeek(h,0,SEEK_END);
 FileWriteString(h,id+"\t"+action+"\t"+IntegerToString((long)utc)+"\t"+DoubleToString(price,_Digits)+"\t"+DoubleToString(News_sl,_Digits)+"\t"+DoubleToString(News_tp,_Digits)+"\t"+DoubleToString(result,2)+"\t"+reason+"\r\n");
 FileFlush(h); FileClose(h);
}
bool News_Digits(string text) {
 if(StringLen(text)==0 || StringLen(text)>12) return false;
 for(int i=0;i<StringLen(text);i++) { ushort c=StringGetCharacter(text,i); if(c<'0' || c>'9') return false; }
 return true;
}
bool News_ValidID(string id) {
 if(StringLen(id)!=64) return false;
 for(int i=0;i<64;i++) { ushort c=StringGetCharacter(id,i); if(!((c>='0' && c<='9') || (c>='a' && c<='f'))) return false; }
 return true;
}
void News_Pause(string reason) {
 // Keep the pending ID until expiry; a transient outage must not consume it forever.
 // No new entry while paused, and confirmation restarts after service recovery.
 News_live_confirmed=false;
 if(!News_active) { News_baseline=0; News_baseline_time=0; }
 News_status=reason;
}
void News_Accept(string line,datetime now) {
 string f[]; if(StringSplit(line,'\t',f)!=4) { News_Pause("WAIT: malformed payload"); return; }
 if(!News_ValidID(f[0]) || !News_Digits(f[1]) || !News_Digits(f[2]) || (f[3]!="1" && f[3]!="-1" && f[3]!="0")) { News_Pause("WAIT: malformed payload"); return; }
 string id=f[0]; long a=StringToInteger(f[1]),e=StringToInteger(f[2]); int d=(int)StringToInteger(f[3]);
 if(a<=0 || e<a || (d!=1 && d!=-1) || now<a || now>e) { News_Pause("WAIT: invalid or expired signal"); return; }
 if(id==News_pending) {
  if(a!=(long)News_available || e!=(long)News_expires || d!=News_direction) { News_Pause("WAIT: inconsistent signal"); return; }
  News_live_confirmed=true; News_last_valid=now;
  News_status=News_active ? "VIRTUAL position active" : "CONNECTED: WAIT price confirmation";
  return;
 }
 if(News_Seen(id)) return;
 // Never queue an old event behind an active position.
 News_Remember(id);
 if(News_active || News_pending!="") { News_Log(id,"WAIT",now,0,0,"busy; publication consumed"); return; }
 News_status="WAIT: price confirmation";
 News_live_confirmed=true; News_last_valid=now;
 News_sl=0; News_tp=0;
 News_pending=id; News_available=(datetime)a; News_expires=(datetime)e; News_direction=d; News_baseline=0;
 News_Log(id,"OBSERVE",now,0,0,"rate hypothesis; awaiting post-availability price");
}
string News_HeaderState(string headers) {
 string lines[];
 StringSplit(headers,'\n',lines);
 for(int i=0;i<ArraySize(lines);i++) {
  string lower=lines[i]; StringToLower(lower);
  if(StringFind(lower,"x-sniper-state:")==0) {
   string value=StringSubstr(lines[i],15); StringTrimLeft(value); StringTrimRight(value);
   if(StringLen(value)>48) return "";
   for(int j=0;j<StringLen(value);j++) {
    ushort c=StringGetCharacter(value,j);
    if(!((c>='A' && c<='Z') || c=='_')) return "";
   }
   return value;
  }
 }
 return "";
}
void News_Receive(datetime now) {
 if(News_Replay || MQLInfoInteger(MQL_TESTER)) {
  while(News_replay_handle!=INVALID_HANDLE) {
   if(News_next=="") { if(FileIsEnding(News_replay_handle)) break; News_next=FileReadString(News_replay_handle); }
   string f[];
   if(StringSplit(News_next,'\t',f)!=4) { News_next=""; continue; }
   if(StringToInteger(f[1])>now) break;
   News_Accept(News_next,now); News_next="";
  }
 } else {
  char request[],response[]; string headers;
  int code=WebRequest("GET",News_ServiceURL,"",200,request,response,headers);
  if(code==200) {
   News_status=News_pending!="" ? "CONNECTED: WAIT price confirmation" : "CONNECTED: WAIT no fresh rate signal";
   string line=CharArrayToString(response,0,-1,CP_UTF8); StringTrimRight(line);
   if(line=="WAIT\t0\t0\t0") {
    string state=News_HeaderState(headers);
    News_Pause(state!="" ? "CONNECTED: WAIT "+state : "CONNECTED: WAIT no fresh rate signal"); return;
   }
   News_live_confirmed=false;
   News_Accept(line,now);
  } else { News_Pause("WAIT: service unavailable ("+IntegerToString(code)+")"); }
 }
}
int News_OnInit() {
 if(News_TesterOrders && !MQLInfoInteger(MQL_TESTER)) { News_status="WAIT: tester orders forbidden live"; return INIT_PARAMETERS_INCORRECT; }
 if(!News_Enabled) { News_status="OFF"; return INIT_SUCCEEDED; }
 if(_Period!=PERIOD_M5 || News_ConfirmationSeconds<1 || News_ConfirmationPoints<=0 || News_StopPoints<=0 || News_TargetPoints<=0 || News_HoldSeconds<1 || News_MaxSpreadPoints<1) return INIT_PARAMETERS_INCORRECT;
 Print("Virtual research only. Confirm symbol is broker GOLD/XAUUSD. No orders. UTC offset=",News_ServerUTCOffsetSeconds);
 if(News_TesterOrders && News_TesterFreshJournal && !News_TesterReset()) return INIT_FAILED;
 // Recover consumed IDs; unresolved virtual trades are not reconstructed across restarts.
 int h=FileOpen(News_JournalFile,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
 if(h!=INVALID_HANDLE) {
  while(!FileIsEnding(h)) { string line=FileReadString(h), f[]; if(StringSplit(line,'\t',f)>1 && !News_Seen(f[0])) News_Remember(f[0]); }
  FileClose(h);
 }
 if(News_Replay || MQLInfoInteger(MQL_TESTER)) {
  News_replay_handle=FileOpen(News_ReplayFile,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
  if(News_replay_handle==INVALID_HANDLE) { Print("News_Replay file missing"); return INIT_FAILED; }
 }
 News_ready=true; News_status="WAIT: no publication received"; return INIT_SUCCEEDED;
}
void News_OnDeinit(const int reason) {
 if(News_replay_handle!=INVALID_HANDLE) FileClose(News_replay_handle);
 if(News_active) Print("UNRESOLVED virtual position on shutdown: ",News_pending);
}
void News_OnTimer() {
 if(!News_Enabled || !News_ready || MQLInfoInteger(MQL_TESTER)) return;
 if(GetTickCount64()-News_last_poll<5000) return;
 News_last_poll=GetTickCount64(); News_Receive(TimeGMT());
}
void News_OnTick() {
 if(!News_Enabled || !News_ready) return;
 MqlTick tick; if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0 || tick.ask<tick.bid) return;
 datetime now=(News_Replay || MQLInfoInteger(MQL_TESTER)) ? tick.time-News_ServerUTCOffsetSeconds : TimeGMT();
 if(News_Replay || MQLInfoInteger(MQL_TESTER)) News_Receive(now);
 if(!News_ready) return;
 if(News_pending=="") return;
 if(News_active && News_TesterOrders) { News_TesterManage(now); return; }
 if(News_active) {
  double exit_price=News_direction==1 ? tick.bid : tick.ask;
  bool stop=News_direction==1 ? exit_price<=News_sl : exit_price>=News_sl;
  bool target=News_direction==1 ? exit_price>=News_tp : exit_price<=News_tp;
  if(stop || target || now-News_opened>=News_HoldSeconds) {
   double pnl=News_direction*(exit_price-News_entry)/_Point;
   News_Log(News_pending,"CLOSE",now,exit_price,pnl,stop?"SL at observed quote":target?"target at observed quote":"time exit at observed quote");
   News_active=false; News_pending=""; News_status="WAIT: virtual position closed";
  }
  return;
 }
 if(now>News_expires) { News_Log(News_pending,"WAIT",now,0,0,"expired without confirmation"); News_pending=""; News_status="WAIT: expired"; return; }
 if(now<News_available) return;
 if(!News_Replay && !MQLInfoInteger(MQL_TESTER) &&
    (!News_live_confirmed || now-News_last_valid>15)) {
  News_Pause("WAIT: service confirmation required"); return;
 }
 double mid=(tick.bid+tick.ask)/2;
 if(News_baseline==0) { News_baseline=mid; News_baseline_time=now; return; }
 if(now-News_baseline_time<News_ConfirmationSeconds || News_direction*(mid-News_baseline)<News_ConfirmationPoints*_Point || (tick.ask-tick.bid)/_Point>News_MaxSpreadPoints) return;
 News_entry=News_direction==1 ? tick.ask : tick.bid;
 News_sl=News_entry-News_direction*News_StopPoints*_Point; News_tp=News_entry+News_direction*News_TargetPoints*_Point;
 if(News_TesterOrders) {
  if(!News_TesterOpen(now,tick)) { News_pending=""; News_status="WAIT: tester entry rejected"; }
  return;
 }
 News_opened=now; News_active=true; News_status=News_direction==1 ? "VIRTUAL BUY" : "VIRTUAL SELL";
 News_Log(News_pending,"OPEN",now,News_entry,0,"spread included; zero latency/slippage/fees; no real order");
 if(!News_ready) News_active=false;
}

void News_InitOptional() {
 int result=News_OnInit();
 if(result!=INIT_SUCCEEDED) { News_ready=false; News_status="WAIT: news initialization failed (check M5/settings/replay)"; Print(News_status); }
}
