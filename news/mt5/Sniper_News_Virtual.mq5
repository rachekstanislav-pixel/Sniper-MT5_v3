#property strict
#property version "0.20"
#property description "Standalone wrapper of the integrated virtual news engine"
#include "SniperNewsTesterSettings.mqh"
#include "SniperNews.mqh"
#include "SniperNewsTester.mqh"
int OnInit() {
 if(!News_TesterValidate(false,false,0)) return INIT_PARAMETERS_INCORRECT;
 int result=News_OnInit();
 if(result!=INIT_SUCCEEDED) return result;
 if(!EventSetTimer(5)) return INIT_FAILED;
 return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { EventKillTimer(); News_OnDeinit(reason); }
void OnTimer() { News_OnTimer(); }
void OnTick() { News_OnTick(); }
