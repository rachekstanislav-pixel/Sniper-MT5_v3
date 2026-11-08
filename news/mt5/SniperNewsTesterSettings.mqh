// Broker-order adapter for the Strategy Tester ONLY. Never used by BASE or live news.
input bool News_TesterFreshJournal=false; // Tester only: reset TESTER_ journal for an independent run
input bool News_TesterOrders=false; // Tester orders only; live requests always forbidden
input ulong News_TesterMagic=9367001;
input double News_TesterLots=0.01;
input int News_TesterDeviationPoints=20;
ulong News_order_position_id=0;
datetime News_order_server_opened=0;
datetime News_last_close_attempt=0;

bool News_TesterValidate(bool baseEnabled,bool diagnostic,ulong baseMagic);
bool News_TesterOpen(datetime now,MqlTick &tick);
void News_TesterManage(datetime now);
bool News_TesterReset();
