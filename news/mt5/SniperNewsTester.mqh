// Tester-only execution; settings/prototypes are in SniperNewsTesterSettings.mqh.
bool News_TesterValidate(bool baseEnabled,bool diagnostic,ulong baseMagic) {
 if(!News_TesterOrders) return true;
 if(!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION) || baseEnabled || diagnostic ||
    News_TesterMagic==0 || News_TesterMagic==baseMagic ||
    !MathIsValidNumber(News_TesterLots) || News_TesterLots<=0 || News_TesterDeviationPoints<0) {
  Print("NEWS TESTER MODE REJECTED: requires Strategy Tester, EnableAutoTrade=false, DiagnosticMode=false, distinct magic and positive lots.");
  return false;
 }
 return true;
}
ulong News_TesterTicket() {
 for(int i=PositionsTotal()-1;i>=0;i--) {
  ulong ticket=PositionGetTicket(i);
  if(ticket>0 && PositionGetString(POSITION_SYMBOL)==_Symbol &&
     (ulong)PositionGetInteger(POSITION_MAGIC)==News_TesterMagic &&
     (News_order_position_id==0 || (ulong)PositionGetInteger(POSITION_IDENTIFIER)==News_order_position_id)) return ticket;
 }
 return 0;
}
bool News_TesterFill(MqlTradeRequest &request) {
 long modes=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
 if((modes & SYMBOL_FILLING_FOK)!=0) request.type_filling=ORDER_FILLING_FOK;
 else if((modes & SYMBOL_FILLING_IOC)!=0) request.type_filling=ORDER_FILLING_IOC;
 else if(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_EXEMODE)!=SYMBOL_TRADE_EXECUTION_MARKET) request.type_filling=ORDER_FILLING_RETURN;
 else return false;
 return true;
}
bool News_TesterSend(MqlTradeRequest &request,MqlTradeResult &result) {
 // Hard runtime guard immediately before EVERY order call, including closes.
 if(!MQLInfoInteger(MQL_TESTER) || !News_TesterOrders) return false;
 if(request.magic!=News_TesterMagic || request.symbol!=_Symbol) return false;
 MqlTradeCheckResult check={};
 if(!News_TesterFill(request) || !OrderCheck(request,check)) {
  Print("NEWS TESTER OrderCheck failed: ",check.retcode," ",check.comment); return false;
 }
 if(!OrderSend(request,result) || (result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_DONE_PARTIAL)) {
  Print("NEWS TESTER OrderSend failed: ",result.retcode," ",result.comment); return false;
 }
 return true;
}
bool News_TesterOpen(datetime now,MqlTick &tick) {
 if(!MQLInfoInteger(MQL_TESTER) || !News_TesterOrders) return false;
 // Refuse mixing with any existing position on the symbol, including netting accounts.
 for(int i=PositionsTotal()-1;i>=0;i--) {
  if(PositionGetTicket(i)>0 && PositionGetString(POSITION_SYMBOL)==_Symbol) {
   News_Log(News_pending,"WAIT",now,0,0,"tester symbol already has a position"); return false;
  }
 }
 double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
 double minVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),maxVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
 if(step<=0 || News_TesterLots<minVolume || News_TesterLots>maxVolume ||
    MathAbs(News_TesterLots/step-MathRound(News_TesterLots/step))>0.000001) {
  News_Log(News_pending,"WAIT",now,0,0,"tester lots incompatible with broker min/max/step"); return false;
 }
 double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
 if(tickSize<=0) return false;
 News_sl=NormalizeDouble(MathRound(News_sl/tickSize)*tickSize,_Digits);
 News_tp=NormalizeDouble(MathRound(News_tp/tickSize)*tickSize,_Digits);
 MqlTradeRequest request={}; MqlTradeResult result={};
 request.action=TRADE_ACTION_DEAL; request.symbol=_Symbol; request.magic=News_TesterMagic;
 request.volume=News_TesterLots; request.type=News_direction==1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
 request.price=News_direction==1 ? tick.ask : tick.bid;
 request.sl=News_sl; request.tp=News_tp; request.deviation=News_TesterDeviationPoints;
 request.comment="NEWS_TEST_"+StringSubstr(News_pending,0,12);
 if(!News_TesterSend(request,result)) { News_Log(News_pending,"WAIT",now,0,0,"tester order rejected; see tester Journal"); return false; }
 News_order_position_id=0;
 if(result.deal>0 && HistoryDealSelect(result.deal)) News_order_position_id=(ulong)HistoryDealGetInteger(result.deal,DEAL_POSITION_ID);
 News_entry=result.price; News_opened=now; News_order_server_opened=TimeCurrent();
 News_active=true; News_last_close_attempt=0;
 ulong ticket=News_TesterTicket();
 if(ticket>0) {
  News_order_position_id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
  News_entry=PositionGetDouble(POSITION_PRICE_OPEN);
  News_sl=PositionGetDouble(POSITION_SL); News_tp=PositionGetDouble(POSITION_TP);
 }
 News_status=News_direction==1 ? "TESTER BUY" : "TESTER SELL";
 News_Log(News_pending,"TESTER_OPEN",now,News_entry,0,"broker-simulated deal; see tester report for volume and costs");
 return true;
}
void News_TesterManage(datetime now) {
 if(!MQLInfoInteger(MQL_TESTER) || !News_TesterOrders) return;
 ulong ticket=News_TesterTicket();
 if(ticket==0) {
  // SL/TP are executed by the tester; reconcile the actual exit deal, not a quote guess.
  if(News_order_position_id>0 && HistorySelect((datetime)((long)News_order_server_opened-1),TimeCurrent())) {
   for(int i=HistoryDealsTotal()-1;i>=0;i--) {
    ulong deal=HistoryDealGetTicket(i);
    if((ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=News_order_position_id ||
       HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
    long entryType=HistoryDealGetInteger(deal,DEAL_ENTRY);
    if(entryType!=DEAL_ENTRY_OUT && entryType!=DEAL_ENTRY_OUT_BY) continue;
    double exitPrice=HistoryDealGetDouble(deal,DEAL_PRICE);
    News_Log(News_pending,"TESTER_CLOSE",now,exitPrice,News_direction*(exitPrice-News_entry)/_Point,
       "tester exit deal; reason="+IntegerToString(HistoryDealGetInteger(deal,DEAL_REASON))+"; money PNL/costs in tester report");
    News_active=false; News_pending=""; News_order_position_id=0;
    News_status="WAIT: tester position closed"; return;
   }
  }
  News_status="WAIT: reconcile tester position"; return;
 }
 if(now-News_opened<News_HoldSeconds || News_last_close_attempt==TimeCurrent()) return;
 News_last_close_attempt=TimeCurrent();
 double volume=PositionGetDouble(POSITION_VOLUME);
 long side=PositionGetInteger(POSITION_TYPE);
 MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
 MqlTradeRequest request={}; MqlTradeResult result={};
 request.action=TRADE_ACTION_DEAL; request.symbol=_Symbol; request.magic=News_TesterMagic;
 request.position=ticket; request.volume=volume; request.deviation=News_TesterDeviationPoints;
 request.type=side==POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
 request.price=side==POSITION_TYPE_BUY ? tick.bid : tick.ask;
 request.comment="NEWS_TEST_TIME_EXIT";
 News_TesterSend(request,result); // Reconcile final/partial closure on following tick.
}

bool News_TesterReset() {
 if(!MQLInfoInteger(MQL_TESTER) || !News_TesterOrders || !News_TesterFreshJournal) return false;
 if(StringFind(News_JournalFile,"TESTER_")!=0 || StringFind(News_JournalFile,"\\")>=0 || StringFind(News_JournalFile,"/")>=0) {
  Print("News_TesterFreshJournal requires a TESTER_ basename, no paths"); return false;
 }
 int h=FileOpen(News_JournalFile,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
 if(h==INVALID_HANDLE) return false;
 FileClose(h); return true;
}
